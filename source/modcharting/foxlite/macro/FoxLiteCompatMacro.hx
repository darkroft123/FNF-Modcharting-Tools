package modcharting.foxlite.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;

/**
 * Makes FoxLite 0.3.0 compile against modern Lime.
 *
 * FoxLite guards its asynchronous texture loading with `lime.system.ThreadPool.isMainThread()`.
 * That method only existed in older Lime, and was dropped from the current one, so four call
 * sites in three classes fail to resolve and take the whole build down:
 *
 *     foxlite.texture.FoxTexture            (x2)
 *     foxlite.mesh.buffer.FoxVertexBuffer
 *     foxlite.loaders.FoxGLTFLoader
 *
 * Rather than fork FoxLite, this macro rewrites the call to the constant `true`, which is the
 * correct answer for every target we care about anyway: texture loading has to happen on the
 * main thread, and the three sites only ever run from it.
 *
 * It follows the same approach as `foxlite.macro.HScriptCompatMacro`, which FoxLite already
 * ships to fix its own Lime drift, so this is a known pattern for this dependency rather than a
 * new mechanism.
 *
 * Wiring, in `extraParams.hxml`:
 *
 *     --macro modcharting.foxlite.macro.FoxLiteCompatMacro.run()
 *
 * Patching is unconditional but harmless. `addGlobalMetadata` only records a string per type
 * name and never resolves it, so the macro is a no op for builds that do not pull FoxLite in.
 * The feature itself stays opt in behind `-D MODCHART_FOXLITE`.
 */
class FoxLiteCompatMacro {
	/** Classes that call the removed Lime method. */
	static final PATCHED_TYPES = ["foxlite.texture.FoxTexture", "foxlite.mesh.buffer.FoxVertexBuffer", "foxlite.loaders.FoxGLTFLoader"];

	public static function run() {
		for (type in PATCHED_TYPES)
			haxe.macro.Compiler.addGlobalMetadata(type, "@:build(modcharting.foxlite.macro.FoxLiteCompatMacro.patchIsMainThread())", true, true, false);
	}

	/**
	 * `@:build` entry point. Inferred return type on purpose: it is exactly what
	 * `Context.getBuildFields()` gives back, and naming `Array<Field>` here pins it to a
	 * structural typedef that the compiler rejects the concrete value against.
	 */
	public static function patchIsMainThread() {
		var fields = Context.getBuildFields();
		for (field in fields) {
			switch (field.kind) {
				case FFun(fn):
					if (fn.expr != null)
						fn.expr = replace(fn.expr);
				default:
			}
		}
		return fields;
	}

	/**
	 * Turns `ThreadPool.isMainThread()` into `true`.
	 *
	 * Matches the whole call rather than just the field access, because rewriting only the
	 * field would leave a `true()` call behind.
	 *
	 * The two matches are separate switches because `Expr` is a class, not an enum, and Haxe
	 * only allows sub patterns inside enum constructors.
	 *
	 * The receiver is not checked. `replace()` is only ever installed on the three classes in
	 * `PATCHED_TYPES`, and the sole `isMainThread()` call in each of them is on `ThreadPool`, so
	 * matching on the field name alone cannot reach anything else. This mirrors
	 * `foxlite.macro.HScriptCompatMacro`, which matches `EField(obj, "__array")` the same way.
	 */
	static function replace(e:Expr):Expr {
		switch (e.expr) {
			case ECall(callee, _):
				switch (callee.expr) {
					case EField(_, "isMainThread"):
						// Built by hand because `macro true` yields an `ExprDef` and `replace()`
						// has to return an `Expr`. `Expr` is `@:structInit`, so `pos` plus `expr`
						// is all it takes.
						//
						// `CIdent("true")` and not a bare `true`: `Constant` is an enum whose
						// constructors are all string or number literals, and a boolean literal is
						// represented as the identifier `true`. Handing it an actual `Bool`
						// produces an AST the compiler cannot serialise, which surfaces much later
						// as the `@:build` result failing to type check.
						return {pos: e.pos, expr: EConst(CIdent("true"))};
					case _:
				}
			case _:
		}
		return ExprTools.map(e, replace);
	}
}
#end
