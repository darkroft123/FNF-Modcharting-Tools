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

	public static function getNoteOffsetX(daNote:Note, instance:ModchartMusicBeatState):Float {
		#if PSYCH
		return daNote.offsetX;
		#elseif LEATHER
		var lane = daNote.noteData;
		if (daNote.mustPress)
			lane += NoteMovement.keyCount;
		var strum = (instance != null && instance.playfieldRenderer != null && instance.playfieldRenderer.strumGroup != null && lane >= 0 && lane < instance.playfieldRenderer.strumGroup.members.length)
			? instance.playfieldRenderer.strumGroup.members[lane] : null;
		if (strum == null)
			return 0;
		// Centers the note on its strum. Computed live instead of cached so that
		// it stays correct when a skin or a scale modifier changes the widths.
		var scaleX:Float = (NoteMovement.defaultScale != null && lane >= 0 && lane < NoteMovement.defaultScale.length)
			? NoteMovement.defaultScale[lane]
			: (daNote.scale != null ? Math.abs(daNote.scale.x) : 1.0);
		var noteW:Float = (daNote.frameWidth > 0 ? daNote.frameWidth : 160) * scaleX;
		return (strum.width - noteW) / 2;
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

	public static function getFakeCrochetAt(time:Float):Float {
		#if LEATHER
		var bpm = Conductor.getBPMAtTime(time);
		if (bpm > 0) return (60 / bpm) * 1000;
		#end
		var bpm = PlayState.SONG != null ? PlayState.SONG.bpm : Conductor.bpm;
		var map = Conductor.bpmChangeMap;
		if (map != null)
			for (change in map)
				if (change.songTime <= time) bpm = change.bpm; else break;
		return (60 / bpm) * 1000;
	}

	public static inline function applyCameraZoomToSprite(sprite:flixel.FlxSprite, camera:flixel.FlxCamera, cameraZoom:Float):Void {
		if (camera != null && camera.zoom != 1.0) {
			var zoom = camera.zoom;
			var zoomEffect = 1.0 - cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				sprite.x = (sprite.x - flixel.FlxG.width * 0.5) * targetZoom + flixel.FlxG.width * 0.5;
				sprite.y = (sprite.y - flixel.FlxG.height * 0.5) * targetZoom + flixel.FlxG.height * 0.5;
				sprite.scale.x *= targetZoom;
				sprite.scale.y *= targetZoom;
			}
		}
	}

	public static inline function applyCameraZoomToMesh(mesh:flixel.FlxStrip, camera:flixel.FlxCamera, cameraZoom:Float):Void {
		if (camera != null && camera.zoom != 1.0 && mesh != null && mesh.vertices != null) {
			var zoom = camera.zoom;
			var zoomEffect = 1.0 - cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				var midX:Float = flixel.FlxG.width * 0.5;
				var midY:Float = flixel.FlxG.height * 0.5;
				var len:Int = mesh.vertices.length;
				for (i in 0...len) {
					if (i % 2 == 0) {
						mesh.vertices[i] = (mesh.vertices[i] - midX) * targetZoom + midX;
					} else {
						mesh.vertices[i] = (mesh.vertices[i] - midY) * targetZoom + midY;
					}
				}
			}
		}
	}

	public static var zNear:Float = 0;
	public static var zFar:Float = 100;
	public static var defaultFOV:Float = 90;

	static var _cachedVec3D:Vector3D = new Vector3D();
	static var _cachedPerspVec3D:Vector3D = new Vector3D();

	static var _perspCacheFOV:Float = -1;
	static var _perspCacheZNear:Float = 0;
	static var _perspCacheZFar:Float = 0;
	static var _perspTanHalfFOV:Float = 0;
	static var _perspZRange:Float = 0;

	/**
		Converts a Vector3D to its in world coordinates using perspective math
	**/
	public static function calculatePerspective(pos:Vector3D, FOV:Float, offsetX:Float = 0, offsetY:Float = 0) {
		/* math from opengl lol
			found from this website https://ogldev.org/www/tutorial12/tutorial12.html
		 */

		// TODO: maybe try using actual matrix???

		if (_perspCacheFOV != FOV || _perspCacheZNear != zNear || _perspCacheZFar != zFar) {
			_perspCacheFOV = FOV;
			_perspCacheZNear = zNear;
			_perspCacheZFar = zFar;
			_perspTanHalfFOV = Math.sin(FOV * 0.5) / Math.cos(FOV * 0.5); // faster tan
			_perspZRange = zNear - zFar;
		}

		var newz = pos.z - 1;
		var zRange = _perspZRange;
		var tanHalfFOV = _perspTanHalfFOV;
		if (pos.z > 1) // if above 1000 z basically
			newz = 0; // should stop weird mirroring with high z values

		// var m00 = 1/(tanHalfFOV);
		// var m11 = 1/tanHalfFOV;
		// var m22 = (-zNear - zFar) / zRange; //isnt this just 1 lol
		// var m23 = 2 * zFar * zNear / zRange;
		// var m32 = 1;

		var xOffsetToCenter = pos.x - (FlxG.width * 0.5); // so the perspective focuses on the center of the screen
		var yOffsetToCenter = pos.y - (FlxG.height * 0.5);

		var zPerspectiveOffset = (newz + (2 * zFar * zNear / zRange));

		// xOffsetToCenter += (offsetX / (1/-zPerspectiveOffset));
		// yOffsetToCenter += (offsetY / (1/-zPerspectiveOffset));
		xOffsetToCenter += (offsetX * -zPerspectiveOffset);
		yOffsetToCenter += (offsetY * -zPerspectiveOffset);

		var xPerspective = xOffsetToCenter * (1 / tanHalfFOV);
		var yPerspective = yOffsetToCenter * tanHalfFOV;
		xPerspective /= -zPerspectiveOffset;
		yPerspective /= -zPerspectiveOffset;

		pos.x = xPerspective + (FlxG.width * 0.5); // offset it back to normal
		pos.y = yPerspective + (FlxG.height * 0.5);
		pos.z = zPerspectiveOffset;

		// pos.z -= 1;
		// pos = perspectiveMatrix.transformVector(pos);

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
		if (phi == 0) {
			pos.x = 0;
			pos.y = radius;
			pos.z = 0;
			return pos;
		}
		var rad = FlxAngle.TO_RAD;
		var sinPhi = Math.sin(phi * rad);
		pos.x = Math.cos(theta * rad) * sinPhi * radius;
		pos.y = Math.cos(phi * rad) * radius;
		pos.z = Math.sin(theta * rad) * sinPhi * radius;

		return pos;
	}

	static var _easeMap:Map<String, Float->Float> = null;
	public static function getFlxEaseByString(?ease:String = '') {
		if (ease == null) ease = '';
		var cleanEase = ease.split(',')[0].toLowerCase().trim();
		if (_easeMap == null) {
			_easeMap = [
				'backin' => FlxEase.backIn,
				'backinout' => FlxEase.backInOut,
				'backout' => FlxEase.backOut,
				'bouncein' => FlxEase.bounceIn,
				'bounceinout' => FlxEase.bounceInOut,
				'bounceout' => FlxEase.bounceOut,
				'circin' => FlxEase.circIn,
				'circinout' => FlxEase.circInOut,
				'circout' => FlxEase.circOut,
				'cubein' => FlxEase.cubeIn,
				'cubeinout' => FlxEase.cubeInOut,
				'cubeout' => FlxEase.cubeOut,
				'elasticin' => FlxEase.elasticIn,
				'elasticinout' => FlxEase.elasticInOut,
				'elasticout' => FlxEase.elasticOut,
				'expoin' => FlxEase.expoIn,
				'expoinout' => FlxEase.expoInOut,
				'expoout' => FlxEase.expoOut,
				'quadin' => FlxEase.quadIn,
				'quadinout' => FlxEase.quadInOut,
				'quadout' => FlxEase.quadOut,
				'quartin' => FlxEase.quartIn,
				'quartinout' => FlxEase.quartInOut,
				'quartout' => FlxEase.quartOut,
				'quintin' => FlxEase.quintIn,
				'quintinout' => FlxEase.quintInOut,
				'quintout' => FlxEase.quintOut,
				'sinein' => FlxEase.sineIn,
				'sineinout' => FlxEase.sineInOut,
				'sineout' => FlxEase.sineOut,
				'smoothstepin' => FlxEase.smoothStepIn,
				'smoothstepinout' => FlxEase.smoothStepInOut,
				'smoothstepout' => FlxEase.smoothStepInOut,
				'smootherstepin' => FlxEase.smootherStepIn,
				'smootherstepinout' => FlxEase.smootherStepInOut,
				'smootherstepout' => FlxEase.smootherStepOut,
			];
		}
		var result = _easeMap.get(cleanEase);
		return result != null ? result : FlxEase.linear;
	}

	public static function getTimeFromBeat(beat:Float) {
		#if LEATHER
		if (Conductor.bpmChangeMap != null) {
			try {
				return Conductor.getTimeInSteps(beat * 4);
			} catch(e:Dynamic) {}
		}
		#end
		var curBpm = PlayState.SONG != null ? PlayState.SONG.bpm : Conductor.bpm;
		if (beat < 0) {
			return beat * (60 / curBpm) * 1000;
		}

		var totalTime:Float = 0;
		var bpmMap = Conductor.bpmChangeMap;
		var bpmIndex:Int = 0;
		var maxBpm = bpmMap != null ? bpmMap.length : 0;
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

	/**
		Splits a comma-separated event data string into top-level arguments,
		ignoring commas inside parentheses `(...)` or brackets `[...]`.
	**/
	public static function splitArgs(str:String, trimTokens:Bool = true):Array<String> {
		if (str == null)
			return [];
		var result:Array<String> = [];
		var current = new StringBuf();
		var depth = 0;
		var len = str.length;
		for (i in 0...len) {
			var c = str.charCodeAt(i);
			if (c == '('.code || c == '['.code) {
				depth++;
				current.addChar(c);
			} else if (c == ')'.code || c == ']'.code) {
				if (depth > 0)
					depth--;
				current.addChar(c);
			} else if (c == ','.code && depth == 0) {
				var tok = current.toString();
				result.push(trimTokens ? tok.trim() : tok);
				current = new StringBuf();
			} else {
				current.addChar(c);
			}
		}
		var lastTok = current.toString();
		if (depth > 0) {
			var lastComma = lastTok.lastIndexOf(',');
			if (lastComma != -1) {
				var before = lastTok.substr(0, lastComma);
				var after = lastTok.substr(lastComma + 1);
				result.push(trimTokens ? before.trim() : before);
				result.push(trimTokens ? after.trim() : after);
				return result;
			}
		}
		result.push(trimTokens ? lastTok.trim() : lastTok);
		return result;
	}

	static function isPureNumber(s:String):Bool {
		var len = s.length;
		if (len == 0)
			return false;
		var i = 0;
		var c = s.charCodeAt(0);
		if (c == '+'.code || c == '-'.code) {
			i++;
			if (i == len)
				return false;
		}
		var hasDigits = false;
		var hasDot = false;
		while (i < len) {
			c = s.charCodeAt(i);
			if (c >= '0'.code && c <= '9'.code) {
				hasDigits = true;
			} else if (c == '.'.code && !hasDot) {
				hasDot = true;
			} else if ((c == 'e'.code || c == 'E'.code) && hasDigits) {
				i++;
				if (i < len && (s.charCodeAt(i) == '+'.code || s.charCodeAt(i) == '-'.code))
					i++;
				if (i >= len)
					return false;
				while (i < len) {
					var ec = s.charCodeAt(i);
					if (ec < '0'.code || ec > '9'.code)
						return false;
					i++;
				}
				return true;
			} else {
				return false;
			}
			i++;
		}
		return hasDigits;
	}

	/**
		Evaluates a numeric value or mathematical expression string (e.g. `Math.sin(beat) * 50`,
		`Math.random()`, `random(-20, 20)`, `180 / Math.PI`, etc.).
		Returns `Math.NaN` if the input is a non-numeric identifier (like a camera layer name).
	**/
	public static function resolveNumeric(rawValue:Dynamic, ?eventBeat:Float):Float {
		if (rawValue == null)
			return Math.NaN;
		if (Std.isOfType(rawValue, Float) || Std.isOfType(rawValue, Int))
			return cast rawValue;

		var s:String = Std.string(rawValue).trim();
		if (s.length == 0)
			return Math.NaN;
		if (isPureNumber(s))
			return Std.parseFloat(s);

		var beatVal:Float = (eventBeat != null && !Math.isNaN(eventBeat)) ? eventBeat : Modifier.beat;
		return _evalMathExpr(s, beatVal);
	}

	static var _exprSrc:String = "";
	static var _exprPos:Int = 0;
	static var _exprLen:Int = 0;
	static var _exprBeat:Float = 0;
	static var _exprError:Bool = false;

	static function _evalMathExpr(expr:String, beatVal:Float):Float {
		var prevSrc = _exprSrc;
		var prevPos = _exprPos;
		var prevLen = _exprLen;
		var prevBeat = _exprBeat;
		var prevErr = _exprError;

		_exprSrc = expr;
		_exprPos = 0;
		_exprLen = expr.length;
		_exprBeat = beatVal;
		_exprError = false;

		var res = _parseTernary();
		_skipSpaces();
		if (_exprError || _exprPos < _exprLen)
			res = Math.NaN;

		_exprSrc = prevSrc;
		_exprPos = prevPos;
		_exprLen = prevLen;
		_exprBeat = prevBeat;
		_exprError = prevErr;

		return res;
	}

	static inline function _skipSpaces():Void {
		while (_exprPos < _exprLen) {
			var c = _exprSrc.charCodeAt(_exprPos);
			if (c == ' '.code || c == '\t'.code || c == '\n'.code || c == '\r'.code)
				_exprPos++;
			else
				break;
		}
	}

	static function _parseTernary():Float {
		var v = _parseOr();
		_skipSpaces();
		if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == '?'.code) {
			_exprPos++;
			var trueVal = _parseTernary();
			_skipSpaces();
			if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == ':'.code) {
				_exprPos++;
				var falseVal = _parseTernary();
				return (v != 0 && !Math.isNaN(v)) ? trueVal : falseVal;
			} else {
				_exprError = true;
				return Math.NaN;
			}
		}
		return v;
	}

	static function _parseOr():Float {
		var v = _parseAnd();
		while (!_exprError) {
			_skipSpaces();
			if (_exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos) == '|'.code && _exprSrc.charCodeAt(_exprPos + 1) == '|'.code) {
				_exprPos += 2;
				var r = _parseAnd();
				v = ((v != 0 && !Math.isNaN(v)) || (r != 0 && !Math.isNaN(r))) ? 1.0 : 0.0;
			} else {
				break;
			}
		}
		return v;
	}

	static function _parseAnd():Float {
		var v = _parseEquality();
		while (!_exprError) {
			_skipSpaces();
			if (_exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos) == '&'.code && _exprSrc.charCodeAt(_exprPos + 1) == '&'.code) {
				_exprPos += 2;
				var r = _parseEquality();
				v = ((v != 0 && !Math.isNaN(v)) && (r != 0 && !Math.isNaN(r))) ? 1.0 : 0.0;
			} else {
				break;
			}
		}
		return v;
	}

	static function _parseEquality():Float {
		var v = _parseRelational();
		while (!_exprError) {
			_skipSpaces();
			if (_exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos) == '='.code && _exprSrc.charCodeAt(_exprPos + 1) == '='.code) {
				_exprPos += 2;
				var r = _parseRelational();
				v = (v == r) ? 1.0 : 0.0;
			} else if (_exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos) == '!'.code && _exprSrc.charCodeAt(_exprPos + 1) == '='.code) {
				_exprPos += 2;
				var r = _parseRelational();
				v = (v != r) ? 1.0 : 0.0;
			} else {
				break;
			}
		}
		return v;
	}

	static function _parseRelational():Float {
		var v = _parseAddSub();
		while (!_exprError) {
			_skipSpaces();
			if (_exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos) == '<'.code && _exprSrc.charCodeAt(_exprPos + 1) == '='.code) {
				_exprPos += 2;
				var r = _parseAddSub();
				v = (v <= r) ? 1.0 : 0.0;
			} else if (_exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos) == '>'.code && _exprSrc.charCodeAt(_exprPos + 1) == '='.code) {
				_exprPos += 2;
				var r = _parseAddSub();
				v = (v >= r) ? 1.0 : 0.0;
			} else if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == '<'.code) {
				_exprPos++;
				var r = _parseAddSub();
				v = (v < r) ? 1.0 : 0.0;
			} else if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == '>'.code) {
				_exprPos++;
				var r = _parseAddSub();
				v = (v > r) ? 1.0 : 0.0;
			} else {
				break;
			}
		}
		return v;
	}

	static function _parseAddSub():Float {
		var v = _parseMulDiv();
		while (!_exprError) {
			_skipSpaces();
			if (_exprPos < _exprLen) {
				var c = _exprSrc.charCodeAt(_exprPos);
				if (c == '+'.code) {
					_exprPos++;
					v += _parseMulDiv();
				} else if (c == '-'.code) {
					_exprPos++;
					v -= _parseMulDiv();
				} else {
					break;
				}
			} else {
				break;
			}
		}
		return v;
	}

	static function _parseMulDiv():Float {
		var v = _parsePow();
		while (!_exprError) {
			_skipSpaces();
			if (_exprPos < _exprLen) {
				var c = _exprSrc.charCodeAt(_exprPos);
				if (c == '*'.code && (_exprPos + 1 >= _exprLen || _exprSrc.charCodeAt(_exprPos + 1) != '*'.code)) {
					_exprPos++;
					v *= _parsePow();
				} else if (c == '/'.code) {
					_exprPos++;
					var r = _parsePow();
					v = (r == 0) ? 0.0 : (v / r);
				} else if (c == '%'.code) {
					_exprPos++;
					var r = _parsePow();
					v = (r == 0) ? 0.0 : (v % r);
				} else {
					break;
				}
			} else {
				break;
			}
		}
		return v;
	}

	static function _parsePow():Float {
		var v = _parseUnary();
		_skipSpaces();
		if (!_exprError && _exprPos < _exprLen) {
			var c = _exprSrc.charCodeAt(_exprPos);
			if (c == '^'.code) {
				_exprPos++;
				var r = _parsePow();
				v = Math.pow(v, r);
			} else if (c == '*'.code && _exprPos + 1 < _exprLen && _exprSrc.charCodeAt(_exprPos + 1) == '*'.code) {
				_exprPos += 2;
				var r = _parsePow();
				v = Math.pow(v, r);
			}
		}
		return v;
	}

	static function _parseUnary():Float {
		_skipSpaces();
		if (_exprPos < _exprLen) {
			var c = _exprSrc.charCodeAt(_exprPos);
			if (c == '+'.code) {
				_exprPos++;
				return _parseUnary();
			} else if (c == '-'.code) {
				_exprPos++;
				return -_parseUnary();
			} else if (c == '!'.code) {
				_exprPos++;
				var v = _parseUnary();
				return (v == 0 || Math.isNaN(v)) ? 1.0 : 0.0;
			}
		}
		return _parsePrimary();
	}

	static function _parsePrimary():Float {
		_skipSpaces();
		if (_exprPos >= _exprLen) {
			_exprError = true;
			return Math.NaN;
		}

		var c = _exprSrc.charCodeAt(_exprPos);

		// Parenthesized expression
		if (c == '('.code) {
			_exprPos++;
			var v = _parseTernary();
			_skipSpaces();
			if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == ')'.code) {
				_exprPos++;
			} else {
				_exprError = true;
				return Math.NaN;
			}
			return v;
		}

		// Numeric literal
		if ((c >= '0'.code && c <= '9'.code) || c == '.'.code) {
			var start = _exprPos;
			while (_exprPos < _exprLen) {
				var nc = _exprSrc.charCodeAt(_exprPos);
				if ((nc >= '0'.code && nc <= '9'.code) || nc == '.'.code) {
					_exprPos++;
				} else if (nc == 'e'.code || nc == 'E'.code) {
					_exprPos++;
					if (_exprPos < _exprLen && (_exprSrc.charCodeAt(_exprPos) == '+'.code || _exprSrc.charCodeAt(_exprPos) == '-'.code))
						_exprPos++;
				} else {
					break;
				}
			}
			var numStr = _exprSrc.substring(start, _exprPos);
			var n = Std.parseFloat(numStr);
			if (Math.isNaN(n))
				_exprError = true;
			return n;
		}

		// Identifier or function call (supports dotted names like Math.sin, FlxG.random.float, etc.)
		if ((c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || c == '_'.code) {
			var start = _exprPos;
			while (_exprPos < _exprLen) {
				var ic = _exprSrc.charCodeAt(_exprPos);
				if ((ic >= 'a'.code && ic <= 'z'.code)
					|| (ic >= 'A'.code && ic <= 'Z'.code)
					|| (ic >= '0'.code && ic <= '9'.code)
					|| ic == '_'.code
					|| ic == '.'.code) {
					_exprPos++;
				} else {
					break;
				}
			}
			var ident = _exprSrc.substring(start, _exprPos).toLowerCase();
			_skipSpaces();

			// Function call
			if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == '('.code) {
				_exprPos++;
				var args:Array<Float> = [];
				_skipSpaces();
				if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) != ')'.code) {
					while (!_exprError) {
						args.push(_parseTernary());
						_skipSpaces();
						if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == ','.code) {
							_exprPos++;
						} else {
							break;
						}
					}
				}
				if (_exprPos < _exprLen && _exprSrc.charCodeAt(_exprPos) == ')'.code) {
					_exprPos++;
				} else {
					_exprError = true;
					return Math.NaN;
				}
				return _callMathFunc(ident, args);
			}

			return _resolveMathConst(ident);
		}

		_exprError = true;
		return Math.NaN;
	}

	static function _resolveMathConst(ident:String):Float {
		switch (ident) {
			case "pi" | "math.pi":
				return Math.PI;
			case "e" | "math.e":
				return 2.718281828459045;
			case "to_rad" | "flxangle.to_rad" | "degtorad":
				return FlxAngle.TO_RAD;
			case "to_deg" | "flxangle.to_deg" | "radtodeg":
				return FlxAngle.TO_DEG;
			case "beat":
				return _exprBeat;
			case "curbeat" | "modifier.beat":
				return Modifier.beat;
			case "step":
				return _exprBeat * 4.0;
			case "curstep":
				return Modifier.beat * 4.0;
			case "bpm" | "conductor.bpm":
				return Conductor.bpm;
			case "crochet" | "conductor.crochet":
				return Conductor.crochet;
			case "songposition" | "conductor.songposition":
				return Conductor.songPosition;
			case "width" | "flxg.width":
				return FlxG.width;
			case "height" | "flxg.height":
				return FlxG.height;
			case "true":
				return 1.0;
			case "false":
				return 0.0;
			default:
				_exprError = true;
				return Math.NaN;
		}
	}

	static function _callMathFunc(ident:String, args:Array<Float>):Float {
		inline function arg(i:Int, def:Float = 0.0):Float {
			return (i < args.length && !Math.isNaN(args[i])) ? args[i] : def;
		}

		switch (ident) {
			case "sin" | "math.sin" | "flxmath.fastsin":
				return Math.sin(arg(0));
			case "cos" | "math.cos" | "flxmath.fastcos":
				return Math.cos(arg(0));
			case "tan" | "math.tan":
				return Math.tan(arg(0));
			case "asin" | "math.asin":
				return Math.asin(arg(0));
			case "acos" | "math.acos":
				return Math.acos(arg(0));
			case "atan" | "math.atan":
				return Math.atan(arg(0));
			case "atan2" | "math.atan2":
				return Math.atan2(arg(0), arg(1));
			case "sindeg" | "sin_deg" | "math.sindeg":
				return Math.sin(arg(0) * FlxAngle.TO_RAD);
			case "cosdeg" | "cos_deg" | "math.cosdeg":
				return Math.cos(arg(0) * FlxAngle.TO_RAD);
			case "tandeg" | "tan_deg" | "math.tandeg":
				return Math.tan(arg(0) * FlxAngle.TO_RAD);
			case "rad" | "degtorad" | "math.rad" | "math.degtorad":
				return arg(0) * FlxAngle.TO_RAD;
			case "deg" | "radtodeg" | "math.deg" | "math.radtodeg":
				return arg(0) * FlxAngle.TO_DEG;
			case "abs" | "math.abs" | "flxmath.absint":
				return Math.abs(arg(0));
			case "floor" | "math.floor" | "math.ffloor" | "ffloor":
				return Math.ffloor(arg(0));
			case "ceil" | "math.ceil" | "math.fceil" | "fceil":
				return Math.fceil(arg(0));
			case "round" | "math.round" | "math.fround" | "fround":
				return Math.fround(arg(0));
			case "sqrt" | "math.sqrt":
				return Math.sqrt(arg(0));
			case "pow" | "math.pow":
				return Math.pow(arg(0), arg(1, 1.0));
			case "exp" | "math.exp":
				return Math.exp(arg(0));
			case "log" | "math.log":
				return Math.log(arg(0));
			case "min" | "math.min":
				if (args.length == 0)
					return 0.0;
				var m = arg(0);
				for (i in 1...args.length)
					if (args[i] < m)
						m = args[i];
				return m;
			case "max" | "math.max":
				if (args.length == 0)
					return 0.0;
				var m = arg(0);
				for (i in 1...args.length)
					if (args[i] > m)
						m = args[i];
				return m;
			case "clamp" | "bound" | "math.clamp" | "flxmath.bound":
				var v = arg(0);
				var lo = args.length > 1 ? arg(1) : v;
				var hi = args.length > 2 ? arg(2) : v;
				return v < lo ? lo : (v > hi ? hi : v);
			case "lerp" | "math.lerp" | "flxmath.lerp":
				return FlxMath.lerp(arg(0), arg(1), arg(2, 0.5));
			case "remap" | "flxmath.remaptorange":
				return FlxMath.remapToRange(arg(0), arg(1), arg(2), arg(3), arg(4));
			case "sign" | "math.sign" | "flxmath.signof":
				var v = arg(0);
				return v > 0 ? 1.0 : (v < 0 ? -1.0 : 0.0);
			case "mod" | "math.mod":
				var a = arg(0);
				var b = arg(1, 1.0);
				return b == 0 ? 0.0 : (((a % b) + b) % b);
			case "random" | "math.random" | "ramdom" | "math.ramdom" | "rand" | "math.rand" | "flxg.random.float":
				if (args.length == 0)
					return Math.random();
				if (args.length == 1)
					return Math.random() * arg(0);
				var a = arg(0);
				var b = arg(1);
				return a <= b ? FlxG.random.float(a, b) : FlxG.random.float(b, a);
			case "randomint" | "randint" | "math.randomint" | "math.randint" | "flxg.random.int":
				if (args.length == 0)
					return FlxG.random.int();
				if (args.length == 1)
					return FlxG.random.int(0, Std.int(arg(0)));
				var a = Std.int(arg(0));
				var b = Std.int(arg(1));
				return a <= b ? FlxG.random.int(a, b) : FlxG.random.int(b, a);
			case "randomsign" | "randsign" | "math.randomsign" | "flxg.random.sign":
				return FlxG.random.sign(args.length > 0 ? arg(0, 50.0) : 50.0);
			case "randombool" | "randbool" | "math.randombool" | "flxg.random.bool":
				return FlxG.random.bool(args.length > 0 ? arg(0, 50.0) : 50.0) ? 1.0 : 0.0;
			default:
				_exprError = true;
				return Math.NaN;
		}
	}
}
