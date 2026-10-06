package modcharting;

import math.FlxPoint3D;
import flixel.addons.effects.FlxSkewedSprite;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxMatrix;
import flixel.graphics.frames.FlxFrame;
import flixel.FlxCamera;
import flixel.math.FlxAngle;

/**
 * Performs 3D rotations on a 2D FlxSprite
 * Also has skew capabilities (2D)
 * @see https://math.stackexchange.com/questions/62182/how-do-i-rotate-a-matrix-transformation-with-a-centered-origin
 * @see https://github.com/raysan5/raylib/blob/7f8bf2233c29ebbd98566962bb3730095b11a4e2/src/raymath.h#L1790
 * @author Vortex
 */
class FlxSprite3D extends FlxSkewedSprite {
	/**
	 * The 3D angle of the sprite.
	 */
	public var angle3D(default, null):FlxPoint3D;

	private var _rotationMatrix(default, null):FlxMatrix;

	/**
	 * Set while FoxLite owns the 3D projection for this sprite.
	 *
	 * Two things have to change when that happens. Flixel routes sprites with no rotation, unit
	 * scale and no blend through `drawSimple()`, which is a plain `copyPixels()` blit that never
	 * touches the shader, so the FoxLite vertex stage would be bypassed entirely. And the
	 * classic `rotateXYZ()` below has to be skipped, or the rotation gets applied twice: once
	 * by that 2D matrix and once by the GPU.
	 *
	 * `PlayfieldRenderer` flips this on the note right before it draws it, and off again after.
	 */
	public var foxLiteActive:Bool = false;

	override function initVars() {
		super.initVars();
		_rotationMatrix = new FlxMatrix();
		angle3D = FlxPoint3D.get();
	}

	override function destroy() {
		angle3D = FlxDestroyUtil.put(angle3D);
		_skewMatrix = null;
		_rotationMatrix = null;
		super.destroy();
	}

	/**
	 * `isSimpleRenderBlit` rather than `isSimpleRender` so the `FlxG.renderTile` behaviour is
	 * left alone: this only has to defeat the blit fast path.
	 */
	override public function isSimpleRenderBlit(?camera:FlxCamera):Bool {
		if (foxLiteActive)
			return false;
		return super.isSimpleRenderBlit(camera);
	}

	override function drawComplex(camera:FlxCamera) {
		_frame.prepareMatrix(_matrix, FlxFrameAngle.ANGLE_0, checkFlipX(), checkFlipY());

		// https://math.stackexchange.com/questions/62182/how-do-i-rotate-a-matrix-transformation-with-a-centered-origin
		// offset
		var xr:Float = -(_matrix.a * origin.x + _matrix.c * origin.y) + origin.x;
		var yr:Float = -(_matrix.b * origin.x + _matrix.d * origin.y) + origin.y;
		_matrix.translate(-xr, -yr);

		if (matrixExposed) {
			_matrix.concat(transformMatrix);
		} else {
			if (bakedRotationAngle <= 0) {
				updateTrig();

				if (angle != 0)
					_matrix.rotateWithTrig(_cosAngle, _sinAngle);
			}

			updateSkewMatrix();
			_matrix.concat(_skewMatrix);
		}

		// The GPU applies angle3D when FoxLite is active, so the classic matrix must not.
		if (!foxLiteActive) {
			rotateXYZ(angle3D);
			// move back after doing rotations
			xr = -(_matrix.a * origin.x + _matrix.c * origin.y) + origin.x;
			yr = -(_matrix.b * origin.x + _matrix.d * origin.y) + origin.y;
			_matrix.translate(xr, yr);
		}

		getScreenPosition(_point, camera);
		_point -= offset;
		_point += origin;
		if (isPixelPerfectRender(camera))
			_point.floor();

		_matrix.translate(_point.x / scale.x, _point.y / scale.y);
		_matrix.translate(-origin.x, -origin.y);
		_matrix.scale(scale.x, scale.y);

		camera.drawPixels(_frame, framePixels, _matrix, colorTransform, blend, antialiasing, shader);
	}

	/**
	 * Rotates a matrix based on X Y and Z angles
	 * @param angle 
	 * @see https://github.com/raysan5/raylib/blob/7f8bf2233c29ebbd98566962bb3730095b11a4e2/src/raymath.h#L1790
	 */
	private function rotateXYZ(angle:FlxPoint3D) {
		var radZ = -FlxAngle.asRadians(angle.z);
		var radY = -FlxAngle.asRadians(angle.y);
		var radX = -FlxAngle.asRadians(angle.x);
		var cosz = Math.cos(radZ);
		var sinz = Math.sin(radZ);
		var cosy = Math.cos(radY);
		var siny = Math.sin(radY);
		var cosx = Math.cos(radX);
		var sinx = Math.sin(radX);

		_rotationMatrix.a = cosz * cosy;
		_rotationMatrix.b = (cosz * siny * sinx) - (sinz * cosx);

		_rotationMatrix.c = sinz * cosy;
		_rotationMatrix.d = (sinz * siny * sinx) + (cosz * cosx);

		_matrix.concat(_rotationMatrix);
	}
}
