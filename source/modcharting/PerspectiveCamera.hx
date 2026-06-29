package modcharting;

import flixel.FlxG;
import math.FlxPoint3D;
import flixel.util.FlxDestroyUtil;
import flixel.graphics.frames.FlxFrame;
import openfl.display.BitmapData;
import flixel.math.FlxMatrix;
import openfl.geom.ColorTransform;
import openfl.display.BlendMode;
import flixel.system.FlxAssets.FlxShader;
import flixel.math.FlxPoint;
import openfl.filters.ShaderFilter;
import openfl.filters.BitmapFilter;
import flixel.util.FlxColor;
import flixel.perspective.PerspectiveShader;
import flixel.FlxCamera;

class PerspectiveCamera extends FlxCamera {
	var perspectiveShader:PerspectiveShader;

	public var z(default, set):Float = 0;
	public var fov(default, set):Float = 90;
	public var angleX(default, set):Float = 0;
	public var angleY(default, set):Float = 0;
	public var originZ:FlxPoint3D = FlxPoint3D.get();
	public var depth:Float = 720;

	public var useGroupAngle(default, set):Bool = false;
	public var groupOrigin:FlxPoint = FlxPoint.get();
	public var groupAngles:FlxPoint = FlxPoint.get();
	public var groupZ(default, set):Float = 0;

	public var useDepthColor(default, set):Bool = false;
	public var depthColor(default, set):FlxColor = 0xFF000000;

	override public function new(x = 0.0, y = 0.0, z = 0.0, width = 0, height = 0, depth = 720, zoom = 0.0) {
		super(x, y, width, height, zoom);
		perspectiveShader = new PerspectiveShader();
		this.depth = depth;
		this.z = z;
		fov = 90;
		angleX = 0;
		angleY = 0;
		centerZOrigin();
		filters = [new ShaderFilter(perspectiveShader)];
	}

	public inline function centerZOrigin():Void {
		originZ.set(width * scaleX / 2, height * scaleY / 2, 0);
	}

	override function destroy() {
		groupAngles = FlxDestroyUtil.put(groupAngles);
		groupOrigin = FlxDestroyUtil.put(groupOrigin);
		originZ.put();
		originZ = null;
		super.destroy();
	}

	override public function drawPixels(?frame:FlxFrame, ?pixels:BitmapData, matrix:FlxMatrix, ?transform:ColorTransform, ?blend:BlendMode,
			?smoothing:Bool = false, ?shader:FlxShader) {
		perspectiveShader.data.centerOffset.value = [
			FlxG.width / 2 - originZ.x - x,
			FlxG.height / 2 - originZ.y - y,
			originZ.z / depth
		]; // it's better to do this in drawComplex than overriding a bunch of functions
		perspectiveShader.data.groupOffset.value = [FlxG.width / 2 - groupOrigin.x, FlxG.height / 2 - groupOrigin.y];
		perspectiveShader.data.groupAngle.value = [groupAngles.x, groupAngles.y];
		super.drawPixels(frame, pixels, matrix, transform, blend, smoothing, shader);
	}

	@:noCompletion
	function set_filters(newFilters:Null<Array<BitmapFilter>>):Null<Array<BitmapFilter>> {
		if (newFilters == null) newFilters = [];
		newFilters.push(new ShaderFilter(perspectiveShader));
		return filters = newFilters;
	}

	@:noCompletion inline function set_z(z:Float):Float {
		this.perspectiveShader.data.zCoord.value = [(z + groupZ) / depth + 1];
		return this.z = z;
	}

	@:noCompletion inline function set_groupZ(z:Float):Float {
		this.perspectiveShader.data.zCoord.value = [(this.z + z) / depth + 1];
		return this.groupZ = z;
	}

	@:noCompletion inline function set_fov(fov:Float):Float {
		this.perspectiveShader.data.fov.value = [fov * Math.PI / 180];
		return this.fov = fov;
	}

	@:noCompletion inline function set_angleX(angleX:Float):Float {
		this.perspectiveShader.data.angleX.value = [angleX * Math.PI / 180];
		return this.angleX = angleX;
	}

	@:noCompletion inline function set_angleY(angleY:Float):Float {
		this.perspectiveShader.data.angleY.value = [angleY * Math.PI / 180];
		return this.angleY = angleY;
	}

	@:noCompletion inline function set_useGroupAngle(v:Bool):Bool {
		perspectiveShader.data.groupedAngle.value = [v];
		return this.useGroupAngle = v;
	}

	@:noCompletion inline function set_useDepthColor(useDepthColor:Bool):Bool {
		this.perspectiveShader.data.useDepthColor.value = [useDepthColor];
		return this.useDepthColor = useDepthColor;
	}

	@:noCompletion inline function set_depthColor(depthColor:FlxColor):FlxColor {
		this.perspectiveShader.data.depthColor.value = [depthColor.redFloat, depthColor.greenFloat, depthColor.blueFloat];
		return this.depthColor = depthColor;
	}
}
