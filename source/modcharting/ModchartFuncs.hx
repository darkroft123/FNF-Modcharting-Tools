package modcharting;

import haxe.Json;
import openfl.net.FileReference;
import flixel.FlxG;
#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
#end

#if LEATHER
import states.PlayState;
import game.Conductor;
import modding.scripts.languages.HScript;
#end

#if (PSYCH && PSYCHVERSION >= "0.7")
#if LUA_ALLOWED
import psychlua.FunkinLua;
import psychlua.HScript as FunkinHScript;
#end
#end

import modcharting.Modifier;
import modcharting.PlayfieldRenderer;
import modcharting.NoteMovement;
import modcharting.ModchartUtil;

import openfl.events.Event;
import openfl.events.IOErrorEvent;

using StringTools;

//for lua and hscript
class ModchartFuncs
{
    public static function loadLuaFunctions(#if (PSYCH && PSYCHVERSION >= "0.7") funkin:FunkinLua #end)
    {
        #if PSYCH
        #if LUA_ALLOWED
        #if !(PSYCHVERSION >= "0.7")
        for (funkin in PlayState.instance.luaArray)
        {
            #if hscript
            funkin.initHaxeModule();
            #end
        #end
            Lua_helper.add_callback(funkin.lua, 'startMod', function(name:String, modClass:String, type:String = '', pf:Int = -1){
                startMod(name,modClass,type,pf);

                PlayState.instance.playfieldRenderer.modifierTable.reconstructTable(); //needs to be reconstructed for lua modcharts
            });
            Lua_helper.add_callback(funkin.lua, 'setMod', function(name:String, value:Float){
                setMod(name, value);
            });
            Lua_helper.add_callback(funkin.lua, 'setSubMod', function(name:String, subValName:String, value:Float){
                setSubMod(name, subValName,value);
            });
            Lua_helper.add_callback(funkin.lua, 'setModTargetLane', function(name:String, value:Int){
                setModTargetLane(name, value);
            });
            Lua_helper.add_callback(funkin.lua, 'setModPlayfield', function(name:String, value:Int){
                setModPlayfield(name,value);
            });
            Lua_helper.add_callback(funkin.lua, 'addPlayfield', function(?x:Float = 0, ?y:Float = 0, ?z:Float = 0){
                addPlayfield(x,y,z);
            });
            Lua_helper.add_callback(funkin.lua, 'removePlayfield', function(idx:Int){
                removePlayfield(idx);
            });
            Lua_helper.add_callback(funkin.lua, 'tweenModifier', function(modifier:String, val:Float, time:Float, ease:String, ?tag:String = null){
                tweenModifier(modifier,val,time,ease,null,tag);
            });
            Lua_helper.add_callback(funkin.lua, 'tweenModifierSubValue', function(modifier:String, subValue:String, val:Float, time:Float, ease:String, ?tag:String = null){
                tweenModifierSubValue(modifier,subValue,val,time,ease,null,tag);
            });
            Lua_helper.add_callback(funkin.lua, 'setModEaseFunc', function(name:String, ease:String){
                setModEaseFunc(name,ease);
            });
            Lua_helper.add_callback(funkin.lua, 'set', function(beat:Float, argsAsString:String){
                set(beat, argsAsString);
            });
            Lua_helper.add_callback(funkin.lua, 'ease', function(beat:Float, time:Float, easeStr:String, argsAsString:String, ?tag:String = null){
                ease(beat, time, easeStr, argsAsString, null, tag);                
            });
            #if !(PSYCHVERSION >= "0.7") } #end
            
            #if (PSYCHVERSION >= "0.7")
                loadHaxeFunctions(funkin);
            #end
        #end
        #if !(PSYCHVERSION >= "0.7")
            #if hscript
            if (FunkinLua.hscript != null)
            {
                FunkinLua.hscript.variables.set('Math', Math);
                FunkinLua.hscript.variables.set('PlayfieldRenderer', PlayfieldRenderer);
                FunkinLua.hscript.variables.set('ModchartUtil', ModchartUtil);
                FunkinLua.hscript.variables.set('Modifier', Modifier);
                FunkinLua.hscript.variables.set('NoteMovement', NoteMovement);
                FunkinLua.hscript.variables.set('NotePositionData', NotePositionData);
                FunkinLua.hscript.variables.set('ModchartFile', ModchartFile);
            }
            #end
        #end
        #end
    }

    
    public static function loadHaxeFunctions(#if PSYCH funkin:FunkinLua#end)
        {
            #if (PSYCH && PSYCHVERSION >= "0.7")
            #if HSCRIPT_ALLOWED
            FunkinHScript.initHaxeModule(funkin);
    
            if (funkin.hscript != null)
            {
                #if (SScript >= "6.1.80")
                    funkin.hscript.setClass(Math);
                    funkin.hscript.setClass(PlayfieldRenderer);
                    funkin.hscript.setClass(ModchartUtil);
                    funkin.hscript.setClass(Modifier);
                    funkin.hscript.setClass(NoteMovement);
                    funkin.hscript.setClass(NotePositionData);
                    funkin.hscript.setClass(ModchartFile);
                #else
                    funkin.hscript.set('Math', Math);
                    funkin.hscript.set('PlayfieldRenderer', PlayfieldRenderer);
                    funkin.hscript.set('ModchartUtil', ModchartUtil);
                    funkin.hscript.set('Modifier', Modifier);
                    funkin.hscript.set('NoteMovement', NoteMovement);
                    funkin.hscript.set('NotePositionData', NotePositionData);
                    funkin.hscript.set('ModchartFile', ModchartFile);
                #end
            }
            #end
            #elseif LEATHER
            /*if(flixel.FlxG.state == states.PlayState.instance){
                HScript.instance.interp.variables.set('PlayfieldRenderer', PlayfieldRenderer);
                HScript.instance.interp.variables.set('ModchartUtil', ModchartUtil);
                HScript.instance.interp.variables.set('Modifier', Modifier);
                HScript.instance.interp.variables.set('NoteMovement', NoteMovement);
                HScript.instance.interp.variables.set('NotePositionData', NotePositionData);
                HScript.instance.interp.variables.set('ModchartFile', ModchartFile);
            }*/
            #end
        }
    #if (HSCRIPT_ALLOWED && PSYCH && PSYCHVERSION >= "0.7")
    public static function loadHScriptFunctions(parent:Dynamic)
    {
        #if HSCRIPT_ALLOWED
        parent.set('startMod', function(name:String, modClass:String, type:String = '', pf:Int = -1){
            startMod(name, modClass, type, pf);

            if (PlayState.instance == FlxG.state && PlayState.instance.playfieldRenderer != null)
            {
                PlayState.instance.playfieldRenderer.modifierTable.reconstructTable(); //needs to be reconstructed for lua modcharts
            }
        });
        parent.set('setMod', function(name:String, value:Float){
            setMod(name, value);
        });
        parent.set('setSubMod', function(name:String, subValName:String, value:Float){
            setSubMod(name, subValName,value);
        });
        parent.set('setModTargetLane', function(name:String, value:Int){
            setModTargetLane(name, value);
        });
        parent.set('setModPlayfield', function(name:String, value:Int){
            setModPlayfield(name,value);
        });
        parent.set('addPlayfield', function(?x:Float = 0, ?y:Float = 0, ?z:Float = 0){
            addPlayfield(x,y,z);
        });
        parent.set('removePlayfield', function(idx:Int){
            removePlayfield(idx);
        });
        parent.set('tweenModifier', function(modifier:String, val:Float, time:Float, ease:String, ?tag:String = null){
            tweenModifier(modifier,val,time,ease,null,tag);
        });
        parent.set('tweenModifierSubValue', function(modifier:String, subValue:String, val:Float, time:Float, ease:String, ?tag:String = null){
            tweenModifierSubValue(modifier,subValue,val,time,ease,null,tag);
        });
        parent.set('setModEaseFunc', function(name:String, ease:String, ?tag:String = null){
            setModEaseFunc(name,ease);
        });
        parent.set('setModValue', function(beat:Float, argsAsString:String){
            set(beat, argsAsString);
        });
        parent.set('easeModValue', function(beat:Float, time:Float, easeStr:String, argsAsString:String, ?tag:String = null){
            ease(beat, time, easeStr, argsAsString, null, tag);
        });
        #end
    }
    #end

    public static function startMod(name:String, modClass:String, type:String = '', pf:Int = -1, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
        {
            instance = PlayState.instance;
            if (instance.playfieldRenderer.modchart != null)
                if (instance.playfieldRenderer.modchart.scriptListen)
                {
                    instance.playfieldRenderer.modchart.data.modifiers.push([name, modClass, type, pf]);
                    trace(name,modClass,type,pf);
                }
        }

        if (instance.playfieldRenderer.modchart != null)
            if (instance.playfieldRenderer.modchart.customModifiers.exists(modClass))
            {
                var modifier = new Modifier(name, getModTypeFromString(type), pf);
                if (instance.playfieldRenderer.modchart.customModifiers.get(modClass).interp != null)
                    instance.playfieldRenderer.modchart.customModifiers.get(modClass).interp.variables.set('instance', instance);
                instance.playfieldRenderer.modchart.customModifiers.get(modClass).initMod(modifier); //need to do it this way instead because using current value in the modifier script didnt work
                //var modifier = instance.playfieldRenderer.modchart.customModifiers.get(modClass).copy();
                //modifier.tag = name; //set correct stuff because its copying shit
                //modifier.playfield = pf;
                //modifier.type = getModTypeFromString(type);
                instance.playfieldRenderer.modifierTable.add(modifier);
                return;
            }

		var mod = Type.resolveClass('modcharting.'+modClass);
		if (mod == null) {mod = Type.resolveClass('modcharting.'+modClass+"Modifier");} //dont need to add "Modifier" to the end of every mod

		if (mod != null)
		{
			var modType = getModTypeFromString(type);
			var modifier:Modifier = cast Type.createInstance(mod, [name, modType, pf]);
			instance.playfieldRenderer.modifierTable.add(modifier);
		}
    }
    public static function getModTypeFromString(type:String)
    {
        var modType = ModifierType.ALL;
        switch (type.toLowerCase())
        {
            case 'player':
                modType = ModifierType.PLAYERONLY;
            case 'opponent':
                modType = ModifierType.OPPONENTONLY;
            case 'lane' | 'lanespecific':
                modType = ModifierType.LANESPECIFIC;
        }
        return modType;
    }

    public static function ensureModifier(name:String, ?instance:ModchartMusicBeatState = null):Modifier
    {
        if (instance == null)
            instance = PlayState.instance;
        if (instance == null || instance.playfieldRenderer == null || instance.playfieldRenderer.modifierTable == null)
            return null;

        var table = instance.playfieldRenderer.modifierTable;
        var modName = name.split(':')[0];

        if (table.modifiers.exists(modName))
            return table.modifiers.get(modName);

        var className:String = modName;
        if (instance.playfieldRenderer != null && instance.playfieldRenderer.modchart != null && instance.playfieldRenderer.modchart.data != null && instance.playfieldRenderer.modchart.data.modifiers != null) {
            for (m in instance.playfieldRenderer.modchart.data.modifiers) {
                if (m[ModchartFile.MOD_NAME] == modName) {
                    className = m[ModchartFile.MOD_CLASS];
                    break;
                }
            }
        }

        // Auto-create modifier by tag and resolved class from chart data
        startMod(modName, className, 'all', -1, instance);
        return table.modifiers.get(modName);
    }

    public static function createModifier(modClass:String, name:String):Modifier
    {
        var mod = Type.resolveClass('modcharting.' + modClass);
        if (mod == null) { mod = Type.resolveClass('modcharting.' + modClass + "Modifier"); }
        if (mod != null)
        {
            try {
                return cast Type.createInstance(mod, [name, ModifierType.ALL, -1]);
            } catch (e:Dynamic) {}
        }
        return null;
    }

    public static function setMod(name:String, value:Float, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        if (instance.playfieldRenderer.modchart != null)
            if (instance.playfieldRenderer.modchart.scriptListen)
            {
                instance.playfieldRenderer.modchart.data.events.push(["set", [0, value+","+name]]);
            }
        var mod = ensureModifier(name, instance);
        if (mod != null)
            mod.currentValue = value;
    }
    public static function setSubMod(name:String, subValName:String, value:Float, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        if (instance.playfieldRenderer.modchart != null)
            if (instance.playfieldRenderer.modchart.scriptListen)
            {
                instance.playfieldRenderer.modchart.data.events.push(["set", [0, value+","+name+":"+subValName]]);
            }
        var mod = ensureModifier(name, instance);
        if (mod != null)
        {
            if (mod.subValues.exists(subValName))
                mod.subValues.get(subValName).value = value;
            else
                mod.subValues.set(subValName, new Modifier.ModifierSubValue(value));
        }
    }
   public static function setModTargetLane(name:String, value:Dynamic, ?instance:ModchartMusicBeatState = null)
        {
        if (instance == null)
            instance = PlayState.instance;

        var mod = ensureModifier(name, instance);
        if (mod != null)
        {
            if (Std.isOfType(value, Array))
            {
                var arr:Array<Dynamic> = cast value;
                if (arr.length == 1) {
                    mod.targetLane = Std.int(arr[0]);
                    mod.targetLanes = null;
                } else {
                    mod.targetLanes = [for (v in arr) Std.int(v)];
                    mod.targetLane = Std.int(arr[0]);
                }
            }
            else
            {
                mod.targetLane = Std.int(value);
                mod.targetLanes = null;
            }
            instance.playfieldRenderer.modifierTable.reconstructTable();
        }
    }
    public static function setModPlayfield(name:String, value:Int, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        var mod = ensureModifier(name, instance);
        if (mod != null)
            mod.playfield = value;
    }
    public static function addPlayfield(?x:Float = 0, ?y:Float = 0, ?z:Float = 0, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        instance.playfieldRenderer.addNewPlayfield(x,y,z);
    }
    public static function removePlayfield(idx:Int, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        instance.playfieldRenderer.playfields.remove(instance.playfieldRenderer.playfields[idx]);
    }

    public static function tweenModifier(modifier:String, val:Float, time:Float, ease:String, ?instance:ModchartMusicBeatState = null, ?tag:String = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        ensureModifier(modifier, instance);
        instance.playfieldRenderer.modifierTable.tweenModifier(modifier, val, time, ease, Modifier.beat, tag);
    }

    public static function tweenModifierSubValue(modifier:String, subValue:String, val:Float, time:Float, ease:String, ?instance:ModchartMusicBeatState = null, ?tag:String = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        ensureModifier(modifier, instance);
        instance.playfieldRenderer.modifierTable.tweenModifierSubValue(modifier, subValue, val, time, ease, Modifier.beat, tag);
    }

    public static function setModEaseFunc(name:String, ease:String, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
            instance = PlayState.instance;
        var mod = ensureModifier(name, instance);
        if (mod != null && Std.isOfType(mod, EaseCurveModifier))
        {
            var temp:Dynamic = mod;
            var castedMod:EaseCurveModifier = temp;
            castedMod.setEase(ease);
        }
    }
    public static function set(beat:Float, argsAsString:String, ?instance:ModchartMusicBeatState = null)
    {
        if (instance == null)
        {
            instance = PlayState.instance;
            if (instance.playfieldRenderer.modchart != null)
                if (instance.playfieldRenderer.modchart.scriptListen)
                {
                    instance.playfieldRenderer.modchart.data.events.push(["set", [beat, argsAsString]]);
                }
        }
        var args = argsAsString.trim().replace(' ', '').split(',');

        instance.playfieldRenderer.eventManager.addEvent(beat, function(arguments:Array<String>) {
            for (i in 0...Math.floor(arguments.length/2))
            {
                var name:String = Std.string(arguments[1 + (i*2)]);
                var value:Float = Std.parseFloat(arguments[0 + (i*2)]);
                if(Math.isNaN(value))
                    value = 0;

                var mod = ensureModifier(name, instance);
                if (mod != null)
                {
                    mod.currentValue = value;
                }
                else 
                {
                    var subModCheck = name.split(':');
                    if (subModCheck.length > 1)
                    {
                        var modName = subModCheck[0];
                        var subModName = subModCheck[1];
                        var parentMod = ensureModifier(modName, instance);
                        if (parentMod != null)
                        {
                            if (parentMod.subValues.exists(subModName))
                                parentMod.subValues.get(subModName).value = value;
                            else
                                parentMod.subValues.set(subModName, new Modifier.ModifierSubValue(value));
                        }
                    }
                }
            }
        }, args);
    }
    public static function ease(beat:Float, time:Float, ease:String, argsAsString:String, ?instance:ModchartMusicBeatState = null, ?tag:String = null):Void
    {
        if (instance == null)
        {
            instance = PlayState.instance;
            if (instance.playfieldRenderer.modchart != null)
                if (instance.playfieldRenderer.modchart.scriptListen)
                {
                    instance.playfieldRenderer.modchart.data.events.push(["ease", [beat, time, ease, argsAsString, tag]]);
                }
        }
            
        if(Math.isNaN(time))
            time = 1;

        var args = argsAsString.trim().replace(' ', '').split(',');

        var func = function(arguments:Array<String>) {
            for (i in 0...Math.floor(arguments.length/2))
            {
                var name:String = Std.string(arguments[1 + (i*2)]);
                var value:Float = Std.parseFloat(arguments[0 + (i*2)]);
                if(Math.isNaN(value))
                    value = 0;
                var subModCheck = name.split(':');
                if (subModCheck.length > 1)
                {
                    var modName = subModCheck[0];
                    var subModName = subModCheck[1];
                    ensureModifier(modName, instance);
                    instance.playfieldRenderer.modifierTable.tweenModifierSubValue(modName, subModName, value, time*Conductor.crochet*0.001, ease, beat, tag);
                }
                else
                {
                    ensureModifier(name, instance);
                    instance.playfieldRenderer.modifierTable.tweenModifier(name, value, time*Conductor.crochet*0.001, ease, beat, tag);
                }
            }
        };
        instance.playfieldRenderer.eventManager.addEvent(beat, func, args);
    }
}
