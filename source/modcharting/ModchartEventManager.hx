package modcharting;

#if LEATHER
import game.Conductor;
#end

class ModchartEventManager {
	public var renderer:PlayfieldRenderer;
	var eventIndex:Int = 0;

	public function new(renderer:PlayfieldRenderer) {
		this.renderer = renderer;
	}

	public var events:Array<ModchartEvent> = [];

	public function update(elapsed:Float) {
		var safety = 0;
		while (eventIndex < events.length && safety < 1000) {
			var event:ModchartEvent = events[eventIndex];
			if (Conductor.songPosition < event.time) {
				break;
			}
			event.func(event.args);
			eventIndex++;
			safety++;
		}
		if (eventIndex > 256) {
			events = events.slice(eventIndex);
			eventIndex = 0;
		}
		Modifier.beat = ((Conductor.songPosition * 0.001) * (Conductor.bpm / 60));
	}

	public inline function addEvent(beat:Float, func:Array<String>->Void, args:Array<String>) {
		var newEvent = new ModchartEvent(ModchartUtil.getTimeFromBeat(beat), func, args);
		var inserted = false;
		for (i in eventIndex...events.length) {
			if (newEvent.time < events[i].time) {
				events.insert(i, newEvent);
				inserted = true;
				break;
			}
		}
		if (!inserted)
			events.push(newEvent);
	}

	public inline function clearEvents() {
		events = [];
		eventIndex = 0;
	}
}
