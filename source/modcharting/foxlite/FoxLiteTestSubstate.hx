package modcharting.foxlite;

#if MODCHART_FOXLITE
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import modcharting.PlayfieldRenderer;
import modcharting.Modifier;
#if LEATHER
import game.Note;
import game.StrumNote;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import objects.Note;
import objects.StrumNote;
#else
import Note;
import StrumNote;
#end

/**
 * Interactive 3D testing substate for FoxLite.
 *
 * Provides live steppers/inputs to modify FOV, Tilt (X/Y/Z), Depth (Scale/Offset),
 * and Note 3D Rotations in real-time with instant visual feedback.
 */
class FoxLiteTestSubstate extends FlxSubState {
	public var renderer:PlayfieldRenderer;

	var bg:FlxSprite;
	var infoText:FlxText;
	var statusText:FlxText;

	var fovStepper:FlxUINumericStepper;
	var tiltXStepper:FlxUINumericStepper;
	var tiltYStepper:FlxUINumericStepper;
	var tiltZStepper:FlxUINumericStepper;
	var depthScaleStepper:FlxUINumericStepper;
	var depthOffsetStepper:FlxUINumericStepper;
	var rotateXStepper:FlxUINumericStepper;
	var rotateYStepper:FlxUINumericStepper;
	var rotateZStepper:FlxUINumericStepper;

	var toggleFoxCheckBox:FlxUICheckBox;
	var resetButton:FlxButton;
	var closeButton:FlxButton;

	// Backup values to restore on exit
	var origFov:Float = 0;
	var origTiltX:Float = 0;
	var origTiltY:Float = 0;
	var origTiltZ:Float = 0;
	var origZScale:Float = 0.001;
	var origZOffset:Float = 0;

	public function new(renderer:PlayfieldRenderer) {
		super();
		this.renderer = renderer;
	}

	override public function create() {
		super.create();

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.65;
		add(bg);

		if (renderer != null && renderer.foxBridge != null) {
			origFov = renderer.foxBridge.fovOffset;
			origTiltX = renderer.foxBridge.tiltX;
			origTiltY = renderer.foxBridge.tiltY;
			origTiltZ = renderer.foxBridge.tiltZ;
			origZScale = renderer.foxBridge.zScale;
			origZOffset = renderer.foxBridge.zOffset;
		}

		var panelBg = new FlxSprite(20, 20).makeGraphic(420, 680, FlxColor.fromRGB(20, 24, 32, 230));
		add(panelBg);

		var title = new FlxText(30, 30, 400, "FoxLite 3D Live Tester", 20);
		title.setFormat(null, 20, FlxColor.CYAN, "left", OUTLINE, FlxColor.BLACK);
		add(title);

		statusText = new FlxText(30, 60, 400, "", 12);
		statusText.color = FlxColor.YELLOW;
		add(statusText);

		var startY:Int = 100;
		var stepY:Int = 48;

		// FOV Offset Stepper
		addLabel(30, startY, "FOV Offset (Degrees):");
		fovStepper = new FlxUINumericStepper(220, startY, 5, 0, -80, 80, 1);
		add(fovStepper);

		// Tilt X Stepper
		startY += stepY;
		addLabel(30, startY, "Tilt X (Degrees):");
		tiltXStepper = new FlxUINumericStepper(220, startY, 5, 0, -180, 180, 1);
		add(tiltXStepper);

		// Tilt Y Stepper
		startY += stepY;
		addLabel(30, startY, "Tilt Y (Degrees):");
		tiltYStepper = new FlxUINumericStepper(220, startY, 5, 0, -180, 180, 1);
		add(tiltYStepper);

		// Tilt Z Stepper
		startY += stepY;
		addLabel(30, startY, "Tilt Z (Degrees):");
		tiltZStepper = new FlxUINumericStepper(220, startY, 5, 0, -180, 180, 1);
		add(tiltZStepper);

		// Depth Scale Stepper (multiplier on 0.001)
		startY += stepY;
		addLabel(30, startY, "Depth Scale (Mult):");
		depthScaleStepper = new FlxUINumericStepper(220, startY, 0.5, 1.0, 0.0, 100.0, 2);
		add(depthScaleStepper);

		// Depth Offset Stepper
		startY += stepY;
		addLabel(30, startY, "Depth Offset:");
		depthOffsetStepper = new FlxUINumericStepper(220, startY, 10, 0, -1000, 1000, 1);
		add(depthOffsetStepper);

		// Rotate X Stepper (Note 3D Pitch)
		startY += stepY;
		addLabel(30, startY, "Rotate X (Pitch):");
		rotateXStepper = new FlxUINumericStepper(220, startY, 5, 0, -180, 180, 1);
		add(rotateXStepper);

		// Rotate Y Stepper (Note 3D Yaw)
		startY += stepY;
		addLabel(30, startY, "Rotate Y (Yaw):");
		rotateYStepper = new FlxUINumericStepper(220, startY, 5, 0, -180, 180, 1);
		add(rotateYStepper);

		// Rotate Z Stepper (Note 3D Roll)
		startY += stepY;
		addLabel(30, startY, "Rotate Z (Roll):");
		rotateZStepper = new FlxUINumericStepper(220, startY, 5, 0, -180, 180, 1);
		add(rotateZStepper);

		// Toggle FoxLite Checkbox
		startY += stepY + 10;
		toggleFoxCheckBox = new FlxUICheckBox(30, startY, null, null, "Enable FoxLite 3D Bridge", 150);
		toggleFoxCheckBox.checked = (renderer != null && renderer.foxBridge != null && renderer.foxBridge.enabled);
		toggleFoxCheckBox.callback = function() {
			if (renderer != null && renderer.foxBridge != null) {
				renderer.foxBridge.enabled = toggleFoxCheckBox.checked;
			}
		};
		add(toggleFoxCheckBox);

		// Buttons
		startY += 40;
		resetButton = new FlxButton(30, startY, "Reset Defaults", function() {
			fovStepper.value = 0;
			tiltXStepper.value = 0;
			tiltYStepper.value = 0;
			tiltZStepper.value = 0;
			depthScaleStepper.value = 1.0;
			depthOffsetStepper.value = 0;
			rotateXStepper.value = 0;
			rotateYStepper.value = 0;
			rotateZStepper.value = 0;
			applyValues();
		});
		add(resetButton);

		closeButton = new FlxButton(150, startY, "Close (ESC)", function() {
			close();
		});
		add(closeButton);

		infoText = new FlxText(30, startY + 45, 400, "Tips:\n- Change values to see notes tilt & project live in 3D!\n- Uncheck checkbox to compare live against 2D mode.", 11);
		infoText.color = FlxColor.WHITE;
		add(infoText);

		// Apply initial values
		applyValues();
	}

	function addLabel(x:Float, y:Float, text:String) {
		var lbl = new FlxText(x, y + 2, 180, text, 12);
		lbl.setFormat(null, 12, FlxColor.WHITE, "left");
		add(lbl);
	}

	function applyValues() {
		if (renderer == null || renderer.foxBridge == null)
			return;

		// 1. Ensure and update FovModifier in modifierTable
		var fovMod = Std.downcast(renderer.modifierTable.modifiers.get('fov'), FovModifier);
		if (fovMod == null) {
			fovMod = new FovModifier('fov');
			renderer.modifierTable.modifiers.set('fov', fovMod);
		}
		fovMod.currentValue = fovStepper.value;
		if (fovMod.subValues.exists('fov'))
			fovMod.subValues.get('fov').value = fovStepper.value;

		// 2. Ensure and update TiltModifier in modifierTable
		var tiltMod = Std.downcast(renderer.modifierTable.modifiers.get('tilt'), TiltModifier);
		if (tiltMod == null) {
			tiltMod = new TiltModifier('tilt');
			renderer.modifierTable.modifiers.set('tilt', tiltMod);
		}
		tiltMod.currentValue = 1.0;
		if (tiltMod.subValues.exists('x')) tiltMod.subValues.get('x').value = tiltXStepper.value;
		if (tiltMod.subValues.exists('y')) tiltMod.subValues.get('y').value = tiltYStepper.value;
		if (tiltMod.subValues.exists('z')) tiltMod.subValues.get('z').value = tiltZStepper.value;

		// 3. Ensure and update DepthModifier in modifierTable
		var depthMod = Std.downcast(renderer.modifierTable.modifiers.get('depth'), DepthModifier);
		if (depthMod == null) {
			depthMod = new DepthModifier('depth');
			renderer.modifierTable.modifiers.set('depth', depthMod);
		}
		depthMod.currentValue = 1.0;
		if (depthMod.subValues.exists('scale')) depthMod.subValues.get('scale').value = DepthModifier.BASE_SCALE * depthScaleStepper.value;
		if (depthMod.subValues.exists('offset')) depthMod.subValues.get('offset').value = depthOffsetStepper.value;

		// 4. Set rotate modifiers if present
		var rotX = renderer.modifierTable.modifiers.get('rotateX');
		if (rotX != null) rotX.currentValue = rotateXStepper.value;

		var rotY = renderer.modifierTable.modifiers.get('rotateY');
		if (rotY != null) rotY.currentValue = rotateYStepper.value;

		var rotZ = renderer.modifierTable.modifiers.get('rotateZ');
		if (rotZ != null) rotZ.currentValue = rotateZStepper.value;

		// 5. Directly set foxBridge values
		renderer.foxBridge.fovOffset = fovStepper.value;
		renderer.foxBridge.setTilt(tiltXStepper.value, tiltYStepper.value, tiltZStepper.value);
		renderer.foxBridge.zScale = DepthModifier.BASE_SCALE * depthScaleStepper.value;
		renderer.foxBridge.zOffset = depthOffsetStepper.value;

		statusText.text = 'FoxLite Status: ' + (renderer.foxBridge.active && renderer.foxBridge.enabled ? 'ACTIVE (3D)' : 'DISABLED (2D)')
			+ '\nEffective FOV: ' + (ModchartUtil.defaultFOV + renderer.foxBridge.fovOffset)
			+ '\nTilt: (' + tiltXStepper.value + '°, ' + tiltYStepper.value + '°, ' + tiltZStepper.value + '°)'
			+ '\nDepth: Scale=' + (renderer.foxBridge.zScale) + ' Offset=' + renderer.foxBridge.zOffset;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		// Apply live input changes
		applyValues();

		if (FlxG.keys.justPressed.ESCAPE) {
			close();
		}
	}
}
#end
