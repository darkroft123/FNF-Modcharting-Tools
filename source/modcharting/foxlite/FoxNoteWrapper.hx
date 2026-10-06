package modcharting.foxlite;

#if MODCHART_FOXLITE
import flixel.FlxSprite;
import flixel.graphics.tile.FlxGraphicsShader;
import foxlite.extras.FlxFox3DSprite;

/**
 * A `FlxFox3DSprite` that remembers the shader the note had before it got here.
 *
 * `FlxFox3DSprite.new()` assigns the shader it is handed to `sprite.shader` and never lets go,
 * which is fine as long as FoxLite owns every frame. It breaks the moment `enabled` is flipped
 * at runtime: the classic renderer would then draw the note through a vertex stage that still
 * ends in FoxLite's projection, fed the uniforms of the last FoxLite frame.
 *
 * Keeping the previous shader here lets `apply()` attach ours for the duration of one note's draw
 * and put the old one back, so a frame that falls back to the classic path renders normally.
 */
class FoxNoteWrapper extends FlxFox3DSprite {
	/** The `FoxSpriteShader` this wrapper owns and bakes uniforms into. */
	public var ownShader:FoxSpriteShader;

	/** Whatever `sprite.shader` was before `ownShader` was attached. */
	public var previousShader:FlxGraphicsShader;

	public function new(target:FlxSprite, shader:FoxSpriteShader, previousShader:FlxGraphicsShader) {
		super(target, shader);
		ownShader = shader;
		this.previousShader = previousShader;
	}

	/**
	 * Puts `ownShader` on the sprite for a draw.
	 *
	 * Re-attaches on every frame rather than assuming it survived, so a note whose shader was
	 * swapped or cleared elsewhere still gets correct uniforms instead of silently rendering with
	 * stale ones.
	 */
	public inline function attachShader():Void {
		if (sprite.shader != ownShader)
			sprite.shader = ownShader;
	}

	/**
	 * Puts `previousShader` back once the FoxLite draw is done.
	 *
	 * Only reverts when the sprite is still holding our shader, so a note that legitimately
	 * changed shader mid frame keeps whatever it picked.
	 */
	public inline function detachShader():Void {
		if (sprite.shader == ownShader)
			sprite.shader = previousShader;
	}
}
#end
