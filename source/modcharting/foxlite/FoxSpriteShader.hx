package modcharting.foxlite;

#if MODCHART_FOXLITE
import flixel.graphics.tile.FlxGraphicsShader;

/**
 * FoxLite's `flixel_sprite.vert`, inlined as a Flixel `GraphicsShader`.
 *
 * The file is copied verbatim from the foxlite repository
 * (`shaders/foxlite/flixel_sprite.vert`) and inlined here on purpose:
 *
 *  - It removes the runtime dependency on the asset path (`assets/shaders/foxlite/...`),
 *    which is the single most common source of breakage when foxlite is dropped into an
 *    engine fork with a non standard `Paths` class (foxlite issues #12 / #13).
 *  - The `@:glVertexSource` metadata is resolved at compile time, so there is no asset
 *    lookup, no IO and no failure mode at song load.
 *
 * How it works
 * ------------
 * `FlxFox3DSprite` writes FoxLite's MVP into `foxlite_MVP_row0..3` and the Flixel camera
 * reference into `flixel_Screen`. This vertex shader then *replaces* Flixel's projection
 * with FoxLite's:
 *
 *   - `openfl_Position` is the sprite's vertex in camera-local pixels (Flixel already
 *     applied scroll/zoom/scale), which is what gives us the note's 2D position for free.
 *   - It is normalised against the camera centre and aspect corrected, giving the quad
 *     local space `x in [-aspect/2, aspect/2]`, `y in [-1/2, 1/2]`.
 *   - `foxlite_MVP * vec4(position, 0, 1)` then places that quad in FoxLite's world.
 *
 * Note that `openfl_Matrix` (Flixel's own projection) is still executed by the inherited
 * `@:glVertexBody` before this body; we simply overwrite `gl_Position`. That is intentional
 * and is how FoxLite's own example works.
 *
 * `openfl.TextureCoordv` / `openfl_Alphav` are untouched, so colour transforms, alpha and
 * pixel perfect rendering all keep behaving exactly as they do in the classic path.
 */
@:glVertexSource('
#pragma header

uniform vec4 flixel_Screen;

// No matrix support. thanks flixel.
uniform vec4 foxlite_MVP_row0;
uniform vec4 foxlite_MVP_row1;
uniform vec4 foxlite_MVP_row2;
uniform vec4 foxlite_MVP_row3;

#define foxlite_MVP mat4( foxlite_MVP_row0, foxlite_MVP_row1, foxlite_MVP_row2, foxlite_MVP_row3)

void main(void) {
	#pragma body

	float camW = 1.0 / flixel_Screen.z;
	float camH = -1.0 / flixel_Screen.w;
	float aspect = camW / camH;

	vec2 normPos;
	normPos.x = ((openfl_Position.x / camW) - 0.5) * aspect;
	normPos.y = -((openfl_Position.y / camH) - 0.5);

	gl_Position = foxlite_MVP * vec4(normPos.xy, 0.0, 1.0);
}
')
class FoxSpriteShader extends FlxGraphicsShader {}
#end