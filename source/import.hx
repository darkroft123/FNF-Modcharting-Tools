// `!macro` is load bearing, not defensive. This file sits at the root of the classpath, so Haxe
// types it in the macro context too, and these imports reach the whole engine
// (`states.PlayState` -> `Popup` -> `AwardsState` -> `utilities.DiscordClient` -> `cpp.ConstCharStar`).
// The `cpp` package is not accessible from a macro, so a single macro on the command line used to
// take the build down with errors pointing at engine files nobody was editing. It also dragged
// flixel-ui into the macro context, where its secondary types (`FlxGraphicAsset`,
// `FlxUITooltipStyle`) failed to resolve and buried the real error.
//
// The guard wraps the whole file rather than sitting on the engine `#if` chain, because `#else`
// and `#elseif` are still reached when the `#if` above them fails, and guarding only the first
// branch just moves the same errors to whichever branch runs under `macro`. The darks engine's own
// `source/import.hx` opens with the same `#if !macro`.
#if !macro
#if LEATHER
import states.PlayState;
import game.SongLoader;
import game.SongLoader.Section as SwagSection;
import game.Note;
import ui.FlxScrollableDropDownMenu;
import game.Conductor;
import utilities.CoolUtil;
import game.StrumNote;
import utilities.NoteVariables;
import states.LoadingState;
import states.MusicBeatState;
import substates.MusicBeatSubstate;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import flixel.addons.ui.FlxUIDropDownMenu;
import backend.Section.SwagSection;
import states.PlayState;
import backend.CoolUtil;
import backend.Conductor;
import backend.ClientPrefs;
import backend.Paths;
import states.LoadingState;
import backend.Difficulty;
#if SCEModchartingTools
import substates.MusicBeatSubstate;
#else
import backend.MusicBeatSubstate;
#end
import objects.Note;
#if SCEModchartingTools
import objects.StrumArrow;
#else
import objects.StrumNote;
#end
import backend.Song;
#else
import Section.SwagSection;
import Song;
import MusicBeatSubstate;
#end

#if (PSYCH && PSYCHVERSION >= "0.7")
#if LUA_ALLOWED
import psychlua.FunkinLua;
import psychlua.HScript as FunkinHScript;
#end
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end
#end
