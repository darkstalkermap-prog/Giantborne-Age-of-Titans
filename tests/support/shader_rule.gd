extends RefCounted
## Runs a shader's own rule on the CPU (M8 screenshot pass fix-up, V1): the scenery fade's shader
## (assets/shaders/scenery_fade.gdshader) and SceneryFade, the copy of its rule the tests measure, must be
## one rule, and test_scenery_fade runs the shader's text against it. This reads a shader's `const float`
## constants, its global uniforms and its functions that return a float, and runs a function's body
## statement by statement in the subset of the shading language the rule is written in: declarations
## (`float x = ...;`, `vec3 v = ...;`), assignments (`x = ...;`, `x /= ...;`), `if (...) { ... }` (no else)
## and `return ...;`. Expressions run in Godot's Expression after a few rewrites: the shader's own
## functions become call_fn(), `a.xyz` and `a.xy` swizzles become xyz(a) and xy(a), `&&` and `||` become
## `and` and `or`, vecN( becomes VectorN(. The language's length, dot, distance, mod and fract are methods
## here; its min, max, floor and smoothstep are Godot's own. Anything outside the subset fails loudly
## (`error` is set and the run returns null), so a rewrite of the shader the subset cannot read breaks
## the test rather than passing it.
## P39f (FOLLOWUPS: the fade's shader test did not cover vertex() and fragment()): run_body() runs a stage's own
## body - vertex() or fragment() - with the built-ins a test hands it (MODEL_MATRIX and INV_VIEW_MATRIX as
## Projections, VERTEX, COLOR as a Vector4, FRAGCOORD, OUTPUT_IS_SRGB, the material's uniforms) and returns
## what it wrote (world_pos, COLOR, ALBEDO, ...) and whether it discarded. The subset grows by what those bodies
## use: assignments to a swizzle (`COLOR.rgb = ...`), `discard;`, the conditional `c ? a : b`, `!`, swizzles of any
## operand (`(M * v).xyz`, `M[3].xyz`, `.rgb` as `.xyz`), vecN() with one value or a vector and a value, and the
## language's pow, mix (with a vector of 0 / 1 for a bvec) and lessThan.

const TYPES := ["float", "int", "bool", "vec2", "vec3", "vec4"]

## name -> float: the shader's `const float` constants.
var constants := {}
## The names of the shader's `global uniform`s, in order.
var global_uniforms := PackedStringArray()
## name -> {"params": PackedStringArray, "body": String}: the functions that return a float.
var functions := {}
## fragment()'s body, and the text of its `if (...) { discard; }` condition ("" when it has none).
var fragment_body := ""
var discard_condition := ""
## P39f: vertex()'s body ("" when the shader has none), and whether the last run_body() discarded.
var vertex_body := ""
var discarded := false
## name -> value: what the shader's globals hold for the next run (its global uniforms, FRAGCOORD).
var globals := {}
## The first failure ("" while none).
var error := ""

var _cache := {}
var _rewritten := {}
var _re_decl := RegEx.create_from_string("^(float|int|bool|vec2|vec3|vec4)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.+)$")
var _re_assign := RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_]*)\\s*([-+*/]?)=\\s*(.+)$")
var _re_swizzle := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*(?:\\[[^\\]]*\\])?)\\.(xyz|xy|rgb)\\b")
var _re_swizzle_assign := RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_]*)\\.(rgb|xyz)\\s*=\\s*(.+)$")


static func from_file(path: String) -> RefCounted:
	var r: RefCounted = (load("res://tests/support/shader_rule.gd") as GDScript).new()
	var code := FileAccess.get_file_as_string(path)
	if code == "":
		r.error = "cannot read %s" % path
		return r
	r.parse(code)
	return r


func parse(code: String) -> void:
	var text := _strip_comments(code)
	for m in RegEx.create_from_string("\\bconst\\s+float\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*([-+0-9.eE]+)\\s*;").search_all(text):
		constants[m.get_string(1)] = float(m.get_string(2))
	for m in RegEx.create_from_string("\\bglobal\\s+uniform\\s+\\w+\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*;").search_all(text):
		global_uniforms.append(m.get_string(1))
	for m in RegEx.create_from_string("\\bfloat\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(([^)]*)\\)\\s*\\{").search_all(text):
		var open := m.get_end() - 1
		var close := _match(text, open, "{", "}")
		if close < 0:
			_fail("%s: no closing brace" % m.get_string(1))
			return
		var params := PackedStringArray()
		for p in m.get_string(2).split(",", false):
			var parts := p.strip_edges().split(" ", false)
			params.append(parts[parts.size() - 1])
		functions[m.get_string(1)] = {"params": params, "body": text.substr(open + 1, close - open - 1)}
	var frag := RegEx.create_from_string("\\bvoid\\s+fragment\\s*\\(\\s*\\)\\s*\\{").search(text)
	if frag != null:
		var body_end := _match(text, frag.get_end() - 1, "{", "}")
		var body := text.substr(frag.get_end(), body_end - frag.get_end())
		fragment_body = body
		var at := body.find("discard")
		var if_at := body.rfind("if", at) if at >= 0 else -1
		if if_at >= 0:
			var open := body.find("(", if_at)
			var close := _match(body, open, "(", ")")
			discard_condition = body.substr(open + 1, close - open - 1).strip_edges()
	var vert := RegEx.create_from_string("\\bvoid\\s+vertex\\s*\\(\\s*\\)\\s*\\{").search(text)
	if vert != null:
		var vend := _match(text, vert.get_end() - 1, "{", "}")
		vertex_body = text.substr(vert.get_end(), vend - vert.get_end())


## P39f: runs vertex() or fragment() (`stage`) with `env` - the built-ins and uniforms it reads, and every name
## it writes (its varyings and outputs, so their assignments land) - and returns the env as the body left it;
## `discarded` says whether it discarded. {} (with `error` set) when it cannot.
func run_body(stage: String, env: Dictionary) -> Dictionary:
	discarded = false
	if error != "":
		return {}
	var body := vertex_body if stage == "vertex" else fragment_body if stage == "fragment" else ""
	if body == "":
		_fail("the shader has no %s()" % stage)
		return {}
	var e := env.duplicate()
	_block(body, e)
	return {} if error != "" else e


## Runs the shader's function `fn_name` with `args` and returns what it returns (null, with `error` set,
## when it cannot).
func run(fn_name: String, args: Array) -> Variant:
	if error != "":
		return null
	var fn: Dictionary = functions.get(fn_name, {})
	if fn.is_empty():
		return _fail("the shader has no function %s" % fn_name)
	var params: PackedStringArray = fn.params
	if params.size() != args.size():
		return _fail("%s takes %d arguments, not %d" % [fn_name, params.size(), args.size()])
	var env := {}
	for i in params.size():
		env[params[i]] = args[i]
	var out := _block(str(fn.body), env)
	if error != "":
		return null
	if not bool(out[0]):
		return _fail("%s returned nothing" % fn_name)
	return out[1]


## Evaluates an expression of the shader (as fragment()'s discard condition) with `env` and the globals.
func evaluate(expr: String, env: Dictionary) -> Variant:
	return null if error != "" else _eval(expr, env.duplicate())


# --------------------------------------------------------------------------- the language's built-ins

func length(v: Variant) -> float:
	return (v as Vector3).length() if v is Vector3 else (v as Vector2).length() if v is Vector2 else absf(float(v))


func dot(a: Variant, b: Variant) -> float:
	return a.dot(b)


func distance(a: Variant, b: Variant) -> float:
	return length(b - a)


func mod(a: Variant, b: float) -> Variant:
	return a - (a / b).floor() * b if (a is Vector2 or a is Vector3) else float(a) - floorf(float(a) / b) * b


func fract(x: Variant) -> Variant:
	return x - x.floor() if (x is Vector2 or x is Vector3) else float(x) - floorf(float(x))


func xyz(v: Variant) -> Vector3:
	if v is Color:
		return Vector3((v as Color).r, (v as Color).g, (v as Color).b)
	return Vector3(v.x, v.y, v.z)


## P39f: vecN() with N values, one value for every component, or a smaller vector and the rest.
func vec2_(a: Variant, b: Variant = null) -> Vector2:
	return Vector2(float(a), float(a)) if b == null else Vector2(float(a), float(b))


func vec3_(a: Variant, b: Variant = null, c: Variant = null) -> Vector3:
	if b == null:
		return Vector3(float(a), float(a), float(a))
	if a is Vector2:
		return Vector3(a.x, a.y, float(b))
	return Vector3(float(a), float(b), float(c))


func vec4_(a: Variant, b: Variant = null, c: Variant = null, d: Variant = null) -> Vector4:
	if b == null:
		return Vector4(float(a), float(a), float(a), float(a))
	if a is Vector3:
		return Vector4(a.x, a.y, a.z, float(b))
	return Vector4(float(a), float(b), float(c), float(d))


## P39f: the language's pow, componentwise on a vector.
func pow_(a: Variant, b: Variant) -> Variant:
	if a is Vector3:
		var e: Vector3 = b if b is Vector3 else Vector3(float(b), float(b), float(b))
		return Vector3(pow(a.x, e.x), pow(a.y, e.y), pow(a.z, e.z))
	return pow(float(a), float(b))


## P39f: the language's mix; a vector of 0 and 1 (lessThan's bvec) picks a component from `b` where it is 1.
func mix(a: Variant, b: Variant, t: Variant) -> Variant:
	if t is Vector3:
		return a * (Vector3.ONE - t) + b * t
	return a + (b - a) * float(t)


## P39f: the conditional operator `c ? a : b`.
func select_(c: Variant, a: Variant, b: Variant) -> Variant:
	return a if bool(c) else b


## P39f: the language's lessThan, as a vector of 1 (true) and 0 (false).
func lessThan(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(1.0 if a.x < b.x else 0.0, 1.0 if a.y < b.y else 0.0, 1.0 if a.z < b.z else 0.0)


func xy(v: Variant) -> Vector2:
	return Vector2(v.x, v.y)


func call_fn(fn_name: String, args: Array) -> Variant:
	return run(fn_name, args)


# --------------------------------------------------------------------------- statements

## Runs the statements of `text`: [true, value] once one returns, else [false, null].
func _block(text: String, env: Dictionary) -> Array:
	var i := 0
	while error == "":
		i = _skip_ws(text, i)
		if i >= text.length():
			return [false, null]
		if _word_at(text, i, "else"):
			_fail("else is outside the subset: %s" % text.substr(i, 40))
			break
		if _word_at(text, i, "if"):
			var open := text.find("(", i)
			var close := _match(text, open, "(", ")")
			if open < 0 or close < 0:
				_fail("an if without its condition: %s" % text.substr(i, 40))
				break
			var cond := text.substr(open + 1, close - open - 1)
			var j := _skip_ws(text, close + 1)
			var body := ""
			if j < text.length() and text[j] == "{":
				var end := _match(text, j, "{", "}")
				body = text.substr(j + 1, end - j - 1)
				i = end + 1
			else:
				var semi := text.find(";", j)
				body = text.substr(j, semi - j + 1)
				i = semi + 1
			if bool(_eval(cond, env)):
				var r := _block(body, env)
				if bool(r[0]) or error != "":
					return r
			continue
		var semi := text.find(";", i)
		if semi < 0:
			_fail("a statement without ';': %s" % text.substr(i, 40))
			break
		# a statement may run over several lines (P39f: vertex()'s colour line)
		var stmt := text.substr(i, semi - i).replace("\n", " ").replace("\t", " ").strip_edges()
		i = semi + 1
		if stmt.begins_with("return "):
			return [true, _eval(stmt.substr(7), env)]
		if stmt == "discard":
			discarded = true
			return [true, null]
		var sw := _re_swizzle_assign.search(stmt)
		if sw != null and env.has(sw.get_string(1)):
			var v3: Variant = _eval(sw.get_string(3), env)
			var whole: Variant = env[sw.get_string(1)]
			if whole is Vector4 and v3 is Vector3:
				env[sw.get_string(1)] = Vector4(v3.x, v3.y, v3.z, (whole as Vector4).w)
				continue
			_fail("a swizzle assignment outside the subset: %s" % stmt)
			break
		var m := _re_decl.search(stmt)
		if m != null:
			env[m.get_string(2)] = _eval(m.get_string(3), env)
			continue
		m = _re_assign.search(stmt)
		if m != null and env.has(m.get_string(1)):
			var v: Variant = _eval(m.get_string(3), env)
			var cur: Variant = env[m.get_string(1)]
			match m.get_string(2):
				"":
					env[m.get_string(1)] = v
				"+":
					env[m.get_string(1)] = cur + v
				"-":
					env[m.get_string(1)] = cur - v
				"*":
					env[m.get_string(1)] = cur * v
				"/":
					env[m.get_string(1)] = cur / v
			continue
		_fail("a statement outside the subset: %s" % stmt)
	return [true, null]


# --------------------------------------------------------------------------- expressions

func _eval(expr: String, env: Dictionary) -> Variant:
	if error != "":
		return null
	var src: String = _rewritten.get(expr, "")
	if src == "":
		src = _rewrite(expr)
		_rewritten[expr] = src
	var merged := constants.duplicate()
	merged.merge(globals, true)
	merged.merge(env, true)
	var names := PackedStringArray(merged.keys())
	var key := src + "|" + ",".join(names)
	var e: Expression = _cache.get(key)
	if e == null:
		e = Expression.new()
		if e.parse(src, names) != OK:
			return _fail("cannot read '%s' (as '%s'): %s" % [expr.strip_edges(), src, e.get_error_text()])
		_cache[key] = e
	var v: Variant = e.execute(merged.values(), self, false)
	if e.has_execute_failed():
		return _fail("cannot run '%s' (as '%s'): %s" % [expr.strip_edges(), src, e.get_error_text()])
	return v


## The expression in Expression's terms (see the class notes).
func _rewrite(expr: String) -> String:
	var s := expr.strip_edges()
	for fn_name: String in functions:
		var re := RegEx.create_from_string("\\b%s\\s*\\(" % fn_name)
		var m := re.search(s)
		while m != null:
			var open := m.get_end() - 1
			var close := _match(s, open, "(", ")")
			if close < 0:
				break
			s = s.substr(0, m.get_start()) + "call_fn(\"%s\", [" % fn_name + s.substr(open + 1, close - open - 1) + "])" \
				+ s.substr(close + 1)
			m = re.search(s)
	s = _ternary(s)
	s = _paren_swizzles(s)
	s = _re_swizzle.sub(s, "$2($1)", true)
	s = s.replace("rgb(", "xyz(")
	s = s.replace("&&", " and ").replace("||", " or ")
	s = RegEx.create_from_string("!(?!=)").sub(s, " not ", true)
	for n in [2, 3, 4]:
		s = RegEx.create_from_string("\\bvec%d\\s*\\(" % n).sub(s, "vec%d_(" % n, true)
	s = RegEx.create_from_string("\\bpow\\s*\\(").sub(s, "pow_(", true)
	return s


## P39f: `c ? a : b` (at the top level of the expression) as select_(c, a, b) (Expression has no conditional
## operator: `a if c else b` reads as `a`).
static func _ternary(s: String) -> String:
	var depth := 0
	var q := -1
	var colon := -1
	for i in s.length():
		var ch := s[i]
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		elif depth == 0 and ch == "?" and q < 0:
			q = i
		elif depth == 0 and ch == ":" and q >= 0 and colon < 0:
			colon = i
	if q < 0 or colon < 0:
		return s
	return "select_((%s), (%s), (%s))" % [s.substr(0, q).strip_edges(), s.substr(q + 1, colon - q - 1).strip_edges(),
		s.substr(colon + 1).strip_edges()]


## P39f: a swizzle of a parenthesised operand, `(M * v).xyz`, as xyz((M * v)).
static func _paren_swizzles(s: String) -> String:
	var out := s
	var at := out.find(").")
	while at >= 0:
		var rest := out.substr(at + 2)
		var sw := ""
		for name: String in ["xyz", "rgb", "xy"]:
			if rest.begins_with(name) and (rest.length() == name.length() or not (rest[name.length()].is_valid_identifier()
					or rest[name.length()].is_valid_int())):
				sw = name
				break
		if sw == "":
			at = out.find(").", at + 2)
			continue
		var depth := 0
		var open := -1
		for i in range(at, -1, -1):
			if out[i] == ")":
				depth += 1
			elif out[i] == "(":
				depth -= 1
				if depth == 0:
					open = i
					break
		if open < 0:
			break
		var fn := "xy" if sw == "xy" else "xyz"
		out = out.substr(0, open) + "%s(%s)" % [fn, out.substr(open, at - open + 1)] + out.substr(at + 2 + sw.length())
		at = out.find(").")
	return out


# --------------------------------------------------------------------------- text

static func _strip_comments(code: String) -> String:
	var out := RegEx.create_from_string("/\\*[\\s\\S]*?\\*/").sub(code, " ", true)
	return RegEx.create_from_string("//[^\\n]*").sub(out, "", true)


## The index of the bracket closing the one at `open` (-1 when there is none).
static func _match(text: String, open: int, a: String, b: String) -> int:
	if open < 0 or open >= text.length() or text[open] != a:
		return -1
	var depth := 0
	for i in range(open, text.length()):
		if text[i] == a:
			depth += 1
		elif text[i] == b:
			depth -= 1
			if depth == 0:
				return i
	return -1


static func _skip_ws(text: String, i: int) -> int:
	while i < text.length() and text[i] in [" ", "\t", "\n", "\r"]:
		i += 1
	return i


static func _word_at(text: String, i: int, word: String) -> bool:
	if text.substr(i, word.length()) != word:
		return false
	var after := i + word.length()
	return after >= text.length() or not (text[after].is_valid_identifier() or text[after].is_valid_int())


func _fail(message: String) -> Variant:
	if error == "":
		error = message
	return null
