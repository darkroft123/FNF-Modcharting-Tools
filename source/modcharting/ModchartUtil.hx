package modcharting;

import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.math.FlxAngle;
import openfl.geom.Vector3D;
import flixel.FlxG;
#if LEATHER
import states.PlayState;
import game.Note;
import game.Conductor;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import states.PlayState;
import objects.Note;
#else
import PlayState;
import Note;
#end

using StringTools;

class ModchartUtil {
	public static inline function getDownscroll(instance:ModchartMusicBeatState) {
		if (instance is ModchartEditorState) {
			return cast(FlxG.state, ModchartEditorState)?.check_downscroll?.checked ?? utilities.Options.getData("downscroll");
		}
		// need to test each engine
		// not expecting all to work
		#if PSYCH
		#if (PSYCHVERSION >= "0.7")
		return ClientPrefs.downScroll;
		#else
		return ClientPrefs.data.downScroll;
		#end
		#elseif LEATHER
		return utilities.Options.getData("downscroll");
		#elseif ANDROMEDA // dunno why youd use this on andromeda but whatever, already got its own cool modchart system
		return instance.currentOptions.downScroll;
		#elseif KADE
		return PlayStateChangeables.useDownscroll;
		#elseif FOREVER_LEGACY // forever might not work just yet because of the multiple strumgroups
		return Init.trueSettings.get('Downscroll');
		#elseif FPSPLUS
		return Config.downscroll;
		#elseif MIC_D_UP // basically no one uses this anymore
		return MainVariables._variables.scroll == "down"
		#else
		return false;
		#end
	}

	public static inline function getMiddlescroll(instance:ModchartMusicBeatState) {
		#if PSYCH
		#if (PSYCHVERSION >= "0.7")
		return ClientPrefs.middleScroll;
		#else
		return ClientPrefs.data.middleScroll;
		#end
		#elseif LEATHER
		return utilities.Options.getData("middlescroll");
		#else
		return false;
		#end
	}

	public static inline function getScrollSpeed(instance:PlayState) {
		if (instance == null)
			return PlayState.SONG.speed;

		#if (PSYCH || ANDROMEDA)
		return instance.songSpeed;
		#elseif LEATHER @:privateAccess
		return instance.speed;
		#elseif KADE
		return PlayStateChangeables.scrollSpeed == 1 ? PlayState.SONG.speed : PlayStateChangeables.scrollSpeed;
		#else
		return PlayState.SONG.speed; // most engines just use this
		#end
	}

	public static function getNoteOffsetX(daNote:Note, instance:ModchartMusicBeatState) {
		#if PSYCH
		return daNote.offsetX;
		#elseif LEATHER
		// fuck
		var offset:Float = 0;

		var lane = daNote.noteData;
		if (daNote.mustPress)
			lane += NoteMovement.keyCount;
		var strum = instance.playfieldRenderer.strumGroup.members[lane];

		var arrayVal = Std.string([lane, daNote.arrow_Type, daNote.isSustainNote]);

		if (!NoteMovement.leatherEngineOffsetStuff.exists(arrayVal)) {
			var tempShit:Float = 0.0;

			var targetX = NoteMovement.defaultStrumX[lane];
			var xPos = targetX;
			while (Std.int(xPos + (daNote.width / 2)) != Std.int(targetX + (strum.width / 2))) {
				xPos += (xPos + daNote.width > targetX + strum.width ? -0.1 : 0.1);
				tempShit += (xPos + daNote.width > targetX + strum.width ? -0.1 : 0.1);
			}
			// trace(arrayVal);
			// trace(tempShit);

			NoteMovement.leatherEngineOffsetStuff.set(arrayVal, tempShit);
		}
		offset = NoteMovement.leatherEngineOffsetStuff.get(arrayVal);

		return offset;
		#else
		return (daNote.isSustainNote ? 37 : 0); // the magic number
		#end
	}

	static var currentFakeCrochet:Float = -1;
	static var lastBpm:Float = -1;

	public static function getFakeCrochet() {
		if (PlayState.SONG.bpm != lastBpm) {
			currentFakeCrochet = (60 / PlayState.SONG.bpm) * 1000; // only need to calculate once
			lastBpm = PlayState.SONG.bpm;
		}
		return currentFakeCrochet;
	}

	public static var zNear:Float = 0;
	public static var zFar:Float = 100;
	public static var defaultFOV:Float = 90;

	static var _cachedVec3D:Vector3D = new Vector3D();
	static var _cachedPerspVec3D:Vector3D = new Vector3D();

	// cached constants for perspective (avoid per-frame recomputation)
	static var _cachedTanHalfFOV:Float = 0;
	static var _cachedInvTanHalfFOV:Float = 0;
	static var _lastCachedFOV:Float = -1;

	static inline function ensureFOVCached(FOV:Float):Void {
		if (FOV != _lastCachedFOV) {
			_cachedTanHalfFOV = Math.sin(FOV * 0.5) / Math.cos(FOV * 0.5);
			_cachedInvTanHalfFOV = 1.0 / _cachedTanHalfFOV;
			_lastCachedFOV = FOV;
		}
	}

	/**
		Converts a Vector3D to its in world coordinates using perspective math
	**/
	public static function calculatePerspective(pos:Vector3D, FOV:Float, offsetX:Float = 0, offsetY:Float = 0) {
		var newz = pos.z - 1;
		var zRange = zNear - zFar;
		if (pos.z > 1)
			newz = 0;

		ensureFOVCached(FOV);

		var halfW = FlxG.width * 0.5;
		var halfH = FlxG.height * 0.5;

		var xOffsetToCenter = pos.x - halfW;
		var yOffsetToCenter = pos.y - halfH;

		var zPerspectiveOffset = (newz + (2 * zFar * zNear / zRange));

		xOffsetToCenter += (offsetX * -zPerspectiveOffset);
		yOffsetToCenter += (offsetY * -zPerspectiveOffset);

		var xPerspective = xOffsetToCenter * _cachedInvTanHalfFOV;
		var yPerspective = yOffsetToCenter * _cachedTanHalfFOV;
		xPerspective /= -zPerspectiveOffset;
		yPerspective /= -zPerspectiveOffset;

		pos.x = xPerspective + halfW;
		pos.y = yPerspective + halfH;
		pos.z = zPerspectiveOffset;

		return pos;
	}

	/**
		Returns in-world 3D coordinates using polar angle, azimuthal angle and a radius.
		(Spherical to Cartesian)

		@param	theta Angle used along the polar axis.
		@param	phi Angle used along the azimuthal axis.
		@param	radius Distance to center.
	**/
	public static function getCartesianCoords3D(theta:Float, phi:Float, radius:Float):Vector3D {
		var pos = _cachedVec3D;
		var rad = FlxAngle.TO_RAD;
		var thetaRad = theta * rad;
		var phiRad = phi * rad;
		var sinPhi = Math.sin(phiRad);
		pos.x = Math.cos(thetaRad) * sinPhi * radius;
		pos.y = Math.cos(phiRad) * radius;
		pos.z = Math.sin(thetaRad) * sinPhi * radius;

		return pos;
	}

	public static function getFlxEaseByString(?ease:String = '') {
		switch (ease.toLowerCase().trim()) {
			case 'backin':
				return FlxEase.backIn;
			case 'backinout':
				return FlxEase.backInOut;
			case 'backout':
				return FlxEase.backOut;
			case 'bouncein':
				return FlxEase.bounceIn;
			case 'bounceinout':
				return FlxEase.bounceInOut;
			case 'bounceout':
				return FlxEase.bounceOut;
			case 'circin':
				return FlxEase.circIn;
			case 'circinout':
				return FlxEase.circInOut;
			case 'circout':
				return FlxEase.circOut;
			case 'cubein':
				return FlxEase.cubeIn;
			case 'cubeinout':
				return FlxEase.cubeInOut;
			case 'cubeout':
				return FlxEase.cubeOut;
			case 'elasticin':
				return FlxEase.elasticIn;
			case 'elasticinout':
				return FlxEase.elasticInOut;
			case 'elasticout':
				return FlxEase.elasticOut;
			case 'expoin':
				return FlxEase.expoIn;
			case 'expoinout':
				return FlxEase.expoInOut;
			case 'expoout':
				return FlxEase.expoOut;
			case 'quadin':
				return FlxEase.quadIn;
			case 'quadinout':
				return FlxEase.quadInOut;
			case 'quadout':
				return FlxEase.quadOut;
			case 'quartin':
				return FlxEase.quartIn;
			case 'quartinout':
				return FlxEase.quartInOut;
			case 'quartout':
				return FlxEase.quartOut;
			case 'quintin':
				return FlxEase.quintIn;
			case 'quintinout':
				return FlxEase.quintInOut;
			case 'quintout':
				return FlxEase.quintOut;
			case 'sinein':
				return FlxEase.sineIn;
			case 'sineinout':
				return FlxEase.sineInOut;
			case 'sineout':
				return FlxEase.sineOut;
			case 'smoothstepin':
				return FlxEase.smoothStepIn;
			case 'smoothstepinout':
				return FlxEase.smoothStepInOut;
			case 'smoothstepout':
				return FlxEase.smoothStepInOut;
			case 'smootherstepin':
				return FlxEase.smootherStepIn;
			case 'smootherstepinout':
				return FlxEase.smootherStepInOut;
			case 'smootherstepout':
				return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	public static function getTimeFromBeat(beat:Float) {
		var bpmMap = Conductor.bpmChangeMap;

		// Negative beats are the pre-roll window: events placed there fire during the
		// "three two one go" countdown, which `PlayState.startCountdown()` implements by starting
		// `Conductor.songPosition` at `-crochet * 5`. Without this branch the loop below becomes
		// the empty range `0...Math.floor(beat)`, `leftOverBeat` comes out as 0 and every negative
		// beat collapses onto time 0, so -1, -2 and -16 would all fire together in no order.
		if (beat < 0) {
			// Nothing in the bpm map sits before time 0, so the whole pre-roll is measured with the
			// opening bpm. That is also what `startCountdown()` uses, since `Conductor.crochet`
			// still holds the first tempo while the position is negative. Taking it from the map
			// rather than from `SONG.bpm` keeps the mapping continuous at beat 0, where the loop
			// below switches to the map on its first iteration.
			var preBpm = bpmMap.length > 0 ? bpmMap[0].bpm : (PlayState.SONG != null ? PlayState.SONG.bpm : Conductor.bpm);
			return (60 / preBpm) * 1000 * beat;
		}

		var totalTime:Float = 0;
		var curBpm = PlayState.SONG != null ? PlayState.SONG.bpm : Conductor.bpm;
		var bpmIndex:Int = 0;
		var maxBpm = bpmMap.length;
		for (i in 0...Math.floor(beat)) {
			while (bpmIndex < maxBpm && totalTime >= bpmMap[bpmIndex].songTime) {
				curBpm = bpmMap[bpmIndex].bpm;
				bpmIndex++;
			}
			totalTime += (60 / curBpm) * 1000;
		}

		var leftOverBeat = beat - Math.floor(beat);
		totalTime += (60 / curBpm) * 1000 * leftOverBeat;

		return totalTime;
	}
}
