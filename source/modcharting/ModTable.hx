package modcharting;

import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import modcharting.Modifier;
#if LEATHER
import game.Conductor;
#end

class ModTable
{
    public var modifiers:Map<String, Modifier> = new Map<String, Modifier>();
    // array mirror of modifiers so the per-frame loops don't pay Map hashing
    public var modsArray:Array<Modifier> = [];
    public var instance:ModchartMusicBeatState = null;
    public var renderer:PlayfieldRenderer = null;

    //The table is used to precalculate all the playfield and lane checks on each modifier,
    //so it should end up with a lot less loops and if checks each frame
    //index table by playfield, then lane, and then loop through each modifier
    public var table:Array<Array<Array<Modifier>>> = [];

    // reusable scratch so applyIncomingAngleMods stops allocating [0,0] per call
    var _incomingAngle:Array<Float> = [0, 0];

    public function new(instance:ModchartMusicBeatState, renderer:PlayfieldRenderer)
    {
        this.instance = instance;
        this.renderer = renderer;
        loadDefaultModifiers();
        reconstructTable();
    }

    inline function syncMods() : Void
    {
        modsArray.resize(0);
        for (mod in modifiers)
            modsArray.push(mod);
    }

    public function add(mod:Modifier) : Void
    {
        mod.instance = instance;
        mod.renderer = renderer;
        remove(mod.tag); //in case you replace one???
        modifiers.set(mod.tag, mod);
        syncMods();
    }
    public function remove(tag:String) : Void
    {
        if (modifiers.exists(tag))
        {
            modifiers.remove(tag);
            syncMods();
        }
    }
    public function clear() : Void
    {
        modifiers.clear();

        loadDefaultModifiers();
        syncMods();
    }
    public function resetMods() : Void
    {
        for (mod in modifiers)
            mod.reset();
    }
    public function setModTargetLane(tag:String, lane:Int) : Void
    {
        if (modifiers.exists(tag))
        {
            modifiers.get(tag).targetLane = lane;
        }
    }

    public function loadDefaultModifiers() : Void
    {
        //default modifiers
        add(new XModifier('x'));
        add(new YModifier('y'));
        add(new ZModifier('z'));
        add(new ConfusionModifier('confusion'));
        add(new CameraModifier('cameramodifier'));
        add(new CameraModifier('camera'));
    
        for (i in 0...(NoteMovement.keyCount+NoteMovement.playerKeyCount))
        {
            add(new XModifier('x'+i, ModifierType.LANESPECIFIC));
            add(new YModifier('y'+i, ModifierType.LANESPECIFIC));
            add(new ZModifier('z'+i, ModifierType.LANESPECIFIC));
            add(new ConfusionModifier('confusion'+i, ModifierType.LANESPECIFIC));
            add(new CameraModifier('cameramodifier'+i, ModifierType.LANESPECIFIC));
            add(new CameraModifier('camera'+i, ModifierType.LANESPECIFIC));
            setModTargetLane('x'+i, i);
            setModTargetLane('y'+i, i);
            setModTargetLane('z'+i, i);
            setModTargetLane('confusion'+i, i);
            setModTargetLane('cameramodifier'+i, i);
            setModTargetLane('camera'+i, i);
        }
    }

    public function reconstructTable() : Void
    {
        table = [];
        syncMods();

        for (pf in 0...renderer.playfields.length)
        {
            if (table[pf] == null)
                table[pf] = [];

            for (lane in 0...NoteMovement.totalKeyCount)
            {
                table[pf].push([]);

                for (mod in modifiers)
                {
                    if (mod.checkLane(lane) && mod.checkPlayField(pf))
                    {
                        table[pf][lane].push(mod); //add mod to table
                    }
                }
            }
        }
    }

    public function applyStrumMods(noteData:NotePositionData, lane:Int, pf:Int) : Void
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList) {
                if (mod.currentValue != mod.baseValue)
                    mod.getStrumPath(noteData, lane, pf);
            }
        }
    }
    public function applyNoteMods(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) : Void
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList) {
                if (mod.currentValue != mod.baseValue)
                    mod.getNotePath(noteData, lane, curPos, pf);
            }
        }
    }
    public function applyNoteDistMods(noteDist:Float, lane:Int, pf:Int) : Float
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList) {
                if (mod.currentValue != mod.baseValue)
                    noteDist = mod.getNoteDist(noteDist, lane, 0, pf);
            }
        }
        return noteDist;
    }
    public function applyCurPosMods(lane:Int, curPos:Float, pf:Int) : Float
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList) {
                if (mod.currentValue != mod.baseValue)
                    curPos = mod.getNoteCurPos(lane, curPos, pf);
            }
        }
        return curPos;
    }
    public function applyIncomingAngleMods(lane:Int, curPos:Float, pf:Int) : Array<Float>
    {
        _incomingAngle[0] = 0;
        _incomingAngle[1] = 0;
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList)
            {
                if (mod.currentValue != mod.baseValue)
                {
                    var ang = mod.getIncomingAngle(lane, curPos, pf);
                    _incomingAngle[0] += ang[0];
                    _incomingAngle[1] += ang[1];
                }
            }
        }
        return _incomingAngle;
    }


    
    public function tweenModifier(modifier:String, val:Float, time:Float, ease:String, beat:Float, ?tag:String = null)
    {
        var modifiers:Map<String, Modifier> = renderer.modifierTable.modifiers;
        if (modifiers.exists(modifier))
        {       
            var mod = modifiers.get(modifier);
            mod.onEvent(val, time, ease, beat);
            var targetVal = (mod.autoReturn && time > 0) ? mod.baseValue : val;
            var easefunc = ModchartUtil.getFlxEaseByString(ease);  
            var startTimeMs = ModchartUtil.getTimeFromBeat(beat);
            var endTimeMs = startTimeMs + (time * 1000);
            if (Conductor.songPosition >= endTimeMs) //cancel if should have ended
            {
                mod.currentValue = targetVal;
                if (mod.autoReturn && targetVal == mod.baseValue)
                {
                    mod.reset();
                }
                return;
            }
            time /= renderer.speed;
            var tween = renderer.createTween(mod, {currentValue: targetVal}, time, {ease: easefunc,
                onComplete: function(twn:FlxTween) {
                    mod.currentValue = targetVal;
                    if (mod.autoReturn && targetVal == mod.baseValue)
                    {
                        mod.reset();
                    }
                    var modifierTag:String = (tag != null ? tag : modifier);
                    #if PSYCH
                        #if (PSYCHVERSION >= "0.7")
                        PlayState.instance.callOnScripts("onModifierComplete", [modifierTag]);
                        #else
                        PlayState.instance.callOnLuas("onModifierComplete", [modifierTag]);
                        #end
                    #end
                }
            });
            if (Conductor.songPosition > startTimeMs) //skip to where it should be i guess??
            {
                @:privateAccess
                tween._secondsSinceStart = Math.min(time, (Conductor.songPosition - startTimeMs) * 0.001);
                @:privateAccess
                tween.update(0);
            }
            if (renderer.editorPaused)
                tween.active = false;
        }
    }

    public function tweenModifierSubValue(modifier:String, subValue:String, val:Float, time:Float, ease:String, beat:Float, ?tag:String = null)
    {
        var modifiers:Map<String, Modifier> = renderer.modifierTable.modifiers;
        if (modifiers.exists(modifier))
        {       
            var mod = modifiers.get(modifier);
            if (!mod.subValues.exists(subValue))
            {
                mod.subValues.set(subValue, new Modifier.ModifierSubValue(0.0));
            }
            if (mod.subValues.exists(subValue))
            {
                mod.onSubModEvent(subValue, val, time, ease, beat);
                var subValObj = mod.subValues.get(subValue);
                var isAutoReturn:Bool = (mod.autoReturn || subValObj.autoReturn);
                var startValue:Float = (isAutoReturn && time > 0) ? subValObj.baseValue : subValObj.value;
                var targetVal:Float = val;
                var easefunc = ModchartUtil.getFlxEaseByString(ease);   
                var tag = modifier+' '+subValue; 

                var startTimeMs = ModchartUtil.getTimeFromBeat(beat);
                var endTimeMs = startTimeMs + (time * 1000);
                if (Conductor.songPosition >= endTimeMs) //cancel if should have ended
                {
                    subValObj.value = (isAutoReturn && time > 0) ? subValObj.baseValue : targetVal;
                    return;
                }
                time /= renderer.speed;
                var tween = renderer.createTweenNum(startValue, targetVal, time, {ease: easefunc,
                    onComplete: function(twn:FlxTween) {
                        subValObj.value = (isAutoReturn && time > 0) ? subValObj.baseValue : targetVal;
                        var modifierTag:String = (tag != null ? tag : '$modifier-$subValue');
                        #if PSYCH
                            #if (PSYCHVERSION >= "0.7")
                            PlayState.instance.callOnScripts("onModifierComplete", [modifier, subValue]);
                            #else
                            PlayState.instance.callOnLuas("onModifierComplete", [modifier, subValue]);
                            #end
                        #end
                    },
                    onUpdate: function(twn:FlxTween) {
                        subValObj.value = FlxMath.lerp(startValue, targetVal, easefunc(twn.percent));
                    }
                });
            if (Conductor.songPosition > startTimeMs) //skip to where it should be i guess??
                {
                    @:privateAccess
                tween._secondsSinceStart = Math.min(time, (Conductor.songPosition - startTimeMs) * 0.001);
                    @:privateAccess
                    tween.update(0);
                }
                if (renderer.editorPaused)
                    tween.active = false;
            }

        }
    }
}
