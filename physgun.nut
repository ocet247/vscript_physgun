const FL_FROZEN = 64;
const FL_ATCONTROLS = 128;
const EFL_KILLME = 1;
const EFL_NO_THINK_FUNCTION = 4194304;
const EF_NODRAW = 32;
const EF_ITEM_BLINK = 256;
const IN_ATTACK = 1;
const IN_DUCK = 4;
const IN_FORWARD = 8;
const IN_BACK = 16;
const IN_ATTACK2 = 2048;
const IN_RELOAD = 8192;
const HIDEHUD_WEAPONSELECTION = 1;
const HUD_PRINTTALK = 3;
const HUD_PRINTCENTER = 4;
const TF_COND_TAUNTING = 7;
const TF_COND_HALLOWEEN_THRILLER = 54;
const TEAM_SPECTATOR = 1;
const TF_TEAM_BLUE = 3;
const MOVETYPE_NONE = 0;
const MOVETYPE_WALK = 2;
const MOVETYPE_FLYGRAVITY = 5;
const MOVETYPE_VPHYSICS = 6;
const MOVECOLLIDE_DEFAULT = 0;
const MOVECOLLIDE_FLY_BOUNCE = 1;
const GR_STATE_PREROUND = 3;

const TF_CLASS_SCOUT = 1;
const TF_CLASS_SNIPER = 2;
const TF_CLASS_SOLDIER = 3;
const TF_CLASS_DEMOMAN = 4;
const TF_CLASS_MEDIC = 5;
const TF_CLASS_HEAVYWEAPONS = 6;
const TF_CLASS_PYRO = 7;
const TF_CLASS_SPY = 8;
const TF_CLASS_ENGINEER = 9;

const MASK_SOLID = 33570827;
const FLT_MAX = 3.402823466e+38;
const TF_AMMO_METAL = 3;
const MAX_WEAPONS = 8;

const PHYSGUN_MODEL_SCALE = 1.5;
const PHYSGUN_BEAM_WIDTH = 3.0;
const PHYSGUN_BEAM_SCROLL = 4.0;
const PHYSGUN_WEAPON_SLOT = 10;
const PHYSGUN_DRAG_MULTIPLIER = 30.0;
const PHYSGUN_SCROLL_DISTANCE = 10.0;
const PHYSGUN_ANGLE_SNAP_MULTIPLE = 45.0;
const PHYSGUN_NEAREST_DISTANCE = 40.0;
const PHYSGUN_FAREST_DISTANCE = 2048.0;
const PHYSGUN_FORGET_GRABBER_DELAY = 3.0;
const SEQ_PHYSGUN_ACTIVE = 0;
const SEQ_PHYSGUN_HOLDING_ENTITY = 1;
const SEQ_PHYSGUN_DRAW = 2;
const SEQ_PHYSGUN_RESET = 3;
const SEQ_PHYSGUN_FREEZE = 4;
const ATM_PHYSGUN_CORE = 1; // Attachment 'core' for worldmodel
// These are the properties that are added into the scope of the physgun user/grabbed object that hold an instance of a class that does all the logic
const PHYSGUN_SCOPE_PROPERTY = "physgun";
const PHYSINFO_SCOPE_PROPERTY = "physinfo";

local ROOT = getroottable();

local ZERO_VECTOR = Vector();
local ZERO_QANGLE = QAngle();

local WORLD_SPAWN = Entities.First();

PrecacheModel("models/weapons/w_physics.mdl");
PrecacheModel("models/weapons/v_superphyscannon.mdl");
PrecacheModel("sprites/laserbeam.spr");

PrecacheSound("weapons/physcannon/physcannon_pickup.wav");
PrecacheSound("weapons/physcannon/physcannon_drop.wav");

PrecacheScriptSound("Halloween.dance_loop");
PrecacheScriptSound("Halloween.dance_howl");

foreach (singleton in [NetProps, Entities]) {
    foreach (name, method in singleton.getclass()) {
        if (name != "IsValid") {
            ROOT[name] <- method.bindenv(singleton);
        }
    }
}

local function create_entity(classname) {
    local entity = CreateByClassname(classname);
    SetPropBool(entity, "m_bForcePurgeFixedupStrings", true);
    return entity;
}

local round = @(number) (number < 0.0 ? number - 0.5 : number + 0.5).tointeger();
local max = @(a, b) a > b ? a : b;
local min = @(a, b) a < b ? a : b;

local function snap_angle_to_multiple(angle, multiple) {
    local new_angle = QAngle(); // to not modify the passed in qangle
    foreach (coordinate, value in angle) {
        new_angle[coordinate] = round(value / multiple) * multiple;
    }
    return new_angle;
}

local function norm_qangle(angle) {
    foreach (coordinate, value in angle) {
        value %= 360.0;
        if (value > 180.0) {
            value -= 360.0;
        } else if (value < -180.0) {
            value += 360.0;
        }
        angle[coordinate] = value;
    }
}

local function set_entity_colour(entity, r, g, b, a) {
    SetPropInt(entity, "m_clrRender", r | g << 8 | b << 16 | a << 24);
}

local function get_scope(entity) {
    local scope = entity.GetScriptScope();
    if (scope) {
        return scope;
    }

    entity.ValidateScriptScope();
    return entity.GetScriptScope();
}

local function get_scope_property_or_null(entity, property) {
    local scope = entity.GetScriptScope();
    if (!(property in scope)) {
        return null;
    }

    return scope[property];
}

local function safe_destroy(entity) {
    if (entity.IsValid()) {
        entity.RemoveEFlags(EFL_KILLME);
        entity.Destroy();
    }
}
local function find_valid_weapon(player) {
    for (local i = 0; i < MAX_WEAPONS; i++) {
        local weapon = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i);
        if (!weapon) {
            continue;
        }

        SetPropBool(weapon, "m_bForcePurgeFixedupStrings", true);
        return weapon;
    }

    return null;
}

local function dummy_ent() {
	// logic_relay does not take up an edict
	local relay = Entities.CreateByClassname("logic_relay")
	NetProps.SetPropBool(relay, "m_bForcePurgeFixedupStrings", true)
	relay.ValidateScriptScope()
	return relay
}

local function run_with_delay(func, delay = 0.0) {
	local dummy = dummy_ent()
	dummy.GetScriptScope()["Run"] <- function[this]()
	{
		dummy.Kill()
		func()
	}

	EntFireByHandle(dummy, "CallScriptFunction", "Run", delay, null, null)
	return dummy
}

local function kill_timer(timer) {
	if (timer && timer.IsValid())
		timer.Kill()
}


/**
 * Represents the world model that should be shown when holding a physgun
 */
local WorldPhysgunStats = class {
    /** @type {string} classname of the weapon */
    weapon = null;
    /** @type {QAngle} rotation of the weapon */
    rotation = null;

    constructor(weapon, rotation = QAngle(0, 90, 180)) {
        this.weapon = weapon;
        this.rotation = rotation;
    }
}

local ClassPhysgunInfo = array(10);
ClassPhysgunInfo[TF_CLASS_SCOUT] = WorldPhysgunStats("tf_weapon_scattergun");
ClassPhysgunInfo[TF_CLASS_SOLDIER] = WorldPhysgunStats("tf_weapon_shotgun_soldier", QAngle(30, 90, 180));
ClassPhysgunInfo[TF_CLASS_PYRO] = WorldPhysgunStats("tf_weapon_shotgun_pyro");
ClassPhysgunInfo[TF_CLASS_DEMOMAN] = WorldPhysgunStats("tf_weapon_grenadelauncher");
ClassPhysgunInfo[TF_CLASS_HEAVYWEAPONS] = WorldPhysgunStats("tf_weapon_shotgun_hwg", QAngle(45, 90, 180));
ClassPhysgunInfo[TF_CLASS_ENGINEER] = WorldPhysgunStats("tf_weapon_shotgun_primary");
ClassPhysgunInfo[TF_CLASS_MEDIC] = WorldPhysgunStats("tf_weapon_syringegun_medic");
ClassPhysgunInfo[TF_CLASS_SNIPER] = WorldPhysgunStats("tf_weapon_smg");
ClassPhysgunInfo[TF_CLASS_SPY] = WorldPhysgunStats("tf_weapon_revolver");

local PhysgunTarget = class {
    /** @type {entity} The target itself*/
    self = null;
    /** @type {boolean} */
    is_grabbed = null;
    /** @type {entity?} */
    grabbed_by = null;
    /** @type {entity} Timer entity that can be killed in order to prevent the execution */
    current_timer = null;
    /** @type {() -> bool} Called externally, answers whether you can grab this target */
    is_invalid = null;
    /** @type {() -> null} Function that freezes the target, can be different depending on the target entity type */
    freeze = null;
    /** @type {() -> null} Function that unfreezes the target, can be different depending on the target entity type */
    unfreeze = null;

    constructor(entity) {
        self = entity;
        get_scope(self)[PHYSINFO_SCOPE_PROPERTY] <- this;

        is_grabbed = false;

        if (self.IsPlayer()) {
            is_invalid = @() !self.IsValid() || !self.IsAlive();

            freeze = function() {
                self.AddFlag(FL_FROZEN);
                self.AddCustomAttribute("voice pitch scale", 0.0, 0.0);

                self.AddCond(TF_COND_HALLOWEEN_THRILLER);
                run_with_delay(function() {
                    self.StopSound("Halloween.dance_howl");
                    self.StopSound("Halloween.dance_loop");
                }, 0.1);
            }
            unfreeze = function() {
                self.SetMoveType(MOVETYPE_WALK, MOVECOLLIDE_DEFAULT);

                self.RemoveFlag(FL_FROZEN);
                self.RemoveCond(TF_COND_HALLOWEEN_THRILLER);
                self.RemoveCustomAttribute("voice pitch scale");
            }
            return;
        }

        is_invalid = @() !self.IsValid();

        if (self.GetMoveType() == MOVETYPE_VPHYSICS) {
            freeze = function () {
                self.AcceptInput("DisableMotion", "", null, null);
            }
            unfreeze = function () {
                self.SetMoveType(MOVETYPE_VPHYSICS, MOVECOLLIDE_DEFAULT);
                self.AcceptInput("EnableMotion", "", null, null);
                self.Teleport(false, ZERO_VECTOR, false, ZERO_QANGLE, true, ZERO_VECTOR);
            }
            return;
        }

        freeze = function() {
            self.AddFlag(FL_FROZEN);
            self.AddEFlags(EFL_NO_THINK_FUNCTION);
        }

        unfreeze = function() {
            self.SetMoveType(MOVETYPE_FLYGRAVITY, MOVECOLLIDE_FLY_BOUNCE);
            self.RemoveFlag(FL_FROZEN);
            self.RemoveEFlags(EFL_NO_THINK_FUNCTION);
        }
    }

    /**
     * @param {entity} grabber New grabber
     */
    function update_grabber(grabber) {
        is_grabbed = true;
        grabbed_by = grabber;
        kill_timer(current_timer);
    }

    /**
     * Should be fired on the target release
     */
    function on_release() {
        is_grabbed = false;
        // Delay the grabber invalidation so OnTakeDamage still works for a short period of time after dropping
        current_timer = run_with_delay(@() grabbed_by = null, PHYSGUN_FORGET_GRABBER_DELAY);
    }
}

class ::PhysgunHolder {
    /** @type {entity} The physgun holder */
    self = null;
    /** @type {entity} tf_wearable(preserved through round restarts) that also has think on it */
    wearable = null;
    /** @type {entity?} */
    last_weapon = null;
    /** @type {integer} */
    last_class = null;

    /** @type {Vector} */
    eye_position = null;
    /** @type {QAngle} */
    eye_angle = null;
    /** @type {Vector} Forward vector of the eyes */
    eye_vector = null;

    /** @type {bool} */
    is_frozen = null;
    /** @type {QAngle} last angle before the user has started to rotate the object */
    freeze_angle = null;

    // All integers
    buttons = null;
    buttons_pressed = null;
    buttons_released = null;
    buttons_last = null;

    // All entities
    dummy = null;
    weapon = null;
    beam = null;
    viewmodel = null;
    viewcontrol = null;

    /** @type {float} */
    next_attack = null;
    /** @type {bool} */
    is_held = null;
    /** @type {bool} */
    force_draw_animation = null;
    /** @type {table} */
    line = null;
    /** @type {bool} */
    can_grab = null;
    /** @type {bool} */
    noclip_mode = null;
    /** @type {bool} */
    active = null;
    /** @type {WorldPhysgunStats} */
    physgun_properties = null;

    /** @type {entity?} Current target */
    target = null;
    /** @type {PhysgunTarget?} Physgun target logic class instance of the current target */
    target_scope = null;
    /** @type {Vector} */
    target_position = null;
    /** @type {float} */
    target_distance = null;
    /** @type {Vector} Offset from the target origin to the grab point of the physgun */
    target_grab_point_offset = null;
    /** @type {QAngle} */
    target_angle = null;
    /** @type {QAngle} Used for rotation to know the actual angle and be able to rotate in 45 degree increments
                       instead of using target_angle and being stuck */
    target_freeze_angle = null;

    /** @type {(to: Vector) -> null} Move the target by 1 tick, used in the Think, can change depending on the noclip mode */
    target_tick = null;

    constructor(player) {
        self = player;
        get_scope(self)[PHYSGUN_SCOPE_PROPERTY] <- this;

        last_class = self.GetPlayerClass();

        wearable = create_entity("tf_wearable");
        SetPropBool(wearable, "m_bValidatedAttachedEntity", true);
        SetPropBool(wearable, "m_AttributeManager.m_Item.m_bInitialized", true);
        wearable.SetModelScale(PHYSGUN_MODEL_SCALE, 0.0);

        wearable.SetTeam(TF_TEAM_BLUE);
        wearable.SetOwner(self);
        wearable.SetModelSimple("models/weapons/w_physics.mdl");
        wearable.DispatchSpawn();
        SetPropInt(wearable, "m_fEffects", EF_NODRAW);
        wearable.AcceptInput("SetParent", "!activator", self, null);

        get_scope(wearable).Think <- Think.bindenv(this);
        AddThinkToEnt(wearable, "Think");

        physgun_properties = ClassPhysgunInfo[last_class];
        reposition_world_model();
        recreate_weapons();

        beam = create_entity("env_quadraticbeam");
        beam.DispatchSpawn();
        beam.AddEFlags(EFL_KILLME);
        beam.SetModel("sprites/laserbeam.spr");
        SetPropFloat(beam, "m_scrollRate", PHYSGUN_BEAM_SCROLL);
        SetPropFloat(beam, "m_flWidth", PHYSGUN_BEAM_WIDTH);
        set_entity_colour(beam, /*r*/117, /*g*/243, /*b*/250, /*a*/255);
        beam.DisableDraw();

        viewmodel = GetPropEntity(self, "m_hViewModel");
        SetPropBool(viewmodel, "m_bForcePurgeFixedupStrings", true);

        viewcontrol = create_entity("point_viewcontrol");
        viewcontrol.DispatchSpawn();
        viewcontrol.AddEFlags(EFL_KILLME);

        buttons_last = 0;

        line = {
            start = null,
            end = null,
            mask = MASK_SOLID,
            ignore = self
        };

        force_draw_animation = false;
        is_frozen = false;
        noclip_mode = false;
        can_grab = true;
    }

    function Think() {
        if (!self.IsAlive()) {
            if (is_held) {
                stop_grabbing();
                force_draw_animation = true;
                update_active_weapon();
            }
            return -1;
        }

        update_active_weapon();

        if (!is_held) {
            return -1;
        }

        if (self.InCond(TF_COND_TAUNTING)) {
            stop_grabbing();
            wearable.DisableDraw();
            return -1;
        } else {
            wearable.EnableDraw();
        }

        buttons = GetPropInt(self, "m_nButtons");
        local buttons_changed = buttons_last ^ buttons;
        buttons_pressed = buttons_changed & buttons;
        buttons_released = buttons_changed & ~buttons;
        buttons_last = buttons;

        eye_position = self.EyePosition();
        if (!is_frozen) {
            eye_angle = self.EyeAngles();
            eye_vector = eye_angle.Forward();
        }

        if (buttons_released & IN_ATTACK) {
            stop_grabbing();
            can_grab = true;
        }

        if (next_attack > Time()) {
            return -1;
        }

        if (target) {
            if (target_scope.is_invalid()) {
                stop_using();
                drop_target();
                can_grab = false;
                return -1;
            }

            if (buttons_pressed & IN_ATTACK2) {
                stop_using();
                generic_freeze_target();
                drop_target();
                can_grab = false;
                return -1;
            }

            if (buttons_released & IN_RELOAD) {
                unfreeze_owner();
            } else if (is_frozen) {
                reposition_target();
            } else if (buttons_pressed & IN_RELOAD) {
                freeze_owner();
            }

            target_position = target.GetOrigin();
            target_tick(eye_position + eye_vector * target_distance - target_grab_point_offset);
            relocate_beam(target_position + target_grab_point_offset);
        } else if (can_grab && buttons & IN_ATTACK) {
            if (!active) {
                beam.EnableDraw();
                self.AddHudHideFlags(HIDEHUD_WEAPONSELECTION); // prevents switching from the weapon
                viewmodel.ResetSequence(SEQ_PHYSGUN_ACTIVE);
                active = true;
            }

            if (try_to_grab_entity()) {
                target_angle = target.EyeAngles();
                target_tick = noclip_mode
                    ? @(vector) target.Teleport(true, vector, true, target_angle, true, ZERO_VECTOR)
                    : @(vector) target.Teleport(false, ZERO_VECTOR, true, target_angle, true, (vector - target_position) * PHYSGUN_DRAG_MULTIPLIER);

                generic_unfreeze_target();
                EmitSoundEx({
                    sound_name = "weapons/physcannon/physcannon_pickup.wav",
                    entity = wearable,
                    sound_level = 99
                });
                viewmodel.ResetSequence(SEQ_PHYSGUN_HOLDING_ENTITY);
            }
            relocate_beam(line.pos);
        } else if (buttons_pressed & IN_ATTACK2) {
            noclip_mode = !noclip_mode;
            ClientPrint(self, HUD_PRINTCENTER, noclip_mode ? "NOCLIP MODE" : "VELOCITY MODE");
        }

        return -1;
    }

    function reposition_world_model() {
        wearable.AcceptInput("SetParentAttachment", "effect_hand_R", null, null);
        wearable.SetAbsAngles(physgun_properties.rotation + self.GetAbsAngles());
    }

    function recreate_weapons() {
        dummy = create_entity("tf_weapon_grapplinghook");
        dummy.DispatchSpawn();
        SetPropEntityArray(self, "m_hMyWeapons", dummy, PHYSGUN_WEAPON_SLOT + 1);

        weapon = create_entity(physgun_properties.weapon);
        weapon.DispatchSpawn();
        weapon.AddAttribute("single wep deploy time decreased", FLT_MAX, -1);
        weapon.SetCustomViewModel("models/weapons/v_superphyscannon.mdl");
        SetPropEntity(weapon, "m_hOwner", self);
        SetPropEntity(weapon, "m_hExtraWearable", wearable);
        SetPropInt(weapon, "m_iPrimaryAmmoType", TF_AMMO_METAL);
    }


    function update_active_weapon() {
        local active_weapon = self.GetActiveWeapon();
        if (active_weapon == last_weapon) {
            return;
        }

        if (active_weapon == dummy) {
            SetPropEntityArray(self, "m_hMyWeapons", weapon, PHYSGUN_WEAPON_SLOT);
            self.Weapon_Switch(weapon);
            SetPropString(dummy, "m_iClassname", "__disable_switch");

            // 1 extra frame of viewmodel is visible with default animation
            // instead of immediately being the drawing animation
            // the fix is just to hide the viewmodel for this 1 tick
            if (!is_held) {
                viewmodel.DisableDraw();
            }
        } else if (active_weapon != weapon) {
            if (last_weapon == weapon) {
                SetPropString(dummy, "m_iClassname", "tf_weapon_grapplinghook");
                SetPropEntityArray(self, "m_hMyWeapons", null, PHYSGUN_WEAPON_SLOT);
                wearable.DisableDraw();

                self.RemoveCustomAttribute("cannot pick up buildings");
                self.Weapon_SetLast(find_valid_weapon(self));

                is_held = false;
                can_grab = true;
            }
        } else if (!is_held) {
            wearable.EnableDraw();
            self.AddCustomAttribute("cannot pick up buildings", 1, 0);

            viewmodel.ResetSequence(SEQ_PHYSGUN_DRAW);
            next_attack = Time() + viewmodel.GetSequenceDuration(SEQ_PHYSGUN_DRAW);

            is_held = true;
            viewmodel.EnableDraw();
        }
        last_weapon = active_weapon;
    }

    function relocate_beam(destination) {
        local start = wearable.GetAttachmentOrigin(ATM_PHYSGUN_CORE);

        //local frame = GetPropInt(wearable, "m_ubInterpolationFrame");
        beam.SetAbsOrigin(start);
        //SetPropInt(wearable, "m_ubInterpolationFrame", frame);

        SetPropVector(beam, "m_targetPosition", destination);
        SetPropVector(beam, "m_controlPosition", start + eye_vector * ((start - destination).Length() * 0.5));
    }

    function try_to_grab_entity() {
        line.start = eye_position;
        line.end = eye_position + eye_vector * PHYSGUN_FAREST_DISTANCE;

        if (!TraceLineEx(line) || !line.hit || line.enthit == WORLD_SPAWN) {
            return false;
        }

        target = line.enthit;
        SetPropBool(target, "m_bForcePurgeFixedupStrings", true);
        // Find the highest parent of an object and move it instead
        local parent = target.GetRootMoveParent();
        if (parent) {
            SetPropBool(parent, "m_bForcePurgeFixedupStrings", true);
            target = parent;
        }

        if (target.GetClassname() == "obj_dispenser") {
            local trigger = FindByClassnameNearest("dispenser_touch_trigger", target.GetOrigin(), 32768.0);
            if (trigger) {
                SetPropBool(trigger, "m_bForcePurgeFixedupStrings", true);
                if (trigger.GetOwner() == target) {
                    trigger.AcceptInput("SetParent", "!activator", target, null);
                }
            }
        }

        target_scope = get_scope_property_or_null(target, PHYSINFO_SCOPE_PROPERTY);
        if (target_scope) {
            if (target_scope.is_grabbed) {
                return false;
            }
        } else {
            target_scope = PhysgunTarget(target);
        }
        target_scope.update_grabber(self);

        SetPropEntity(target, "m_hPhysicsAttacker", self);

        target_distance = max(PHYSGUN_NEAREST_DISTANCE, (line.pos - eye_position).Length());
        target_grab_point_offset = (line.pos - target.GetOrigin());

        return true;
    }

    function stop_using() {
        beam.DisableDraw();
        self.RemoveHudHideFlags(HIDEHUD_WEAPONSELECTION);
        stop_current_sequence();
        active = false;
    }

    function drop_target() {
        if (target.IsValid()) {
            target_scope.on_release();
        }
        target = null;
        EmitSoundEx({
            sound_name = "weapons/physcannon/physcannon_drop.wav",
            entity = wearable,
            sound_level = 99
        });
        if (is_frozen) {
            unfreeze_owner();
        }
    }
    // Convenience wrapper
    function stop_grabbing() {
        if (active) {
            stop_using();
            if (target) {
                drop_target();
            }
        }
    }

    function generic_freeze_target() {
        target_scope.freeze();

        target.SetMoveType(MOVETYPE_NONE, MOVECOLLIDE_DEFAULT);
        // Resets velocity
        target.Teleport(false, ZERO_VECTOR, false, ZERO_QANGLE, true, ZERO_VECTOR);

        SetPropInt(target, "m_fEffects", GetPropInt(target, "m_fEffects") | EF_ITEM_BLINK);
        SetPropBool(target, "m_bClientSideAnimation", false);

        viewmodel.ResetSequence(SEQ_PHYSGUN_FREEZE);
        next_attack = Time() + 0.5;
    }

    function generic_unfreeze_target() {
        target_scope.unfreeze();

        SetPropInt(target, "m_fEffects", GetPropInt(target, "m_fEffects") & ~EF_ITEM_BLINK);
        SetPropBool(target, "m_bClientSideAnimation", true);
    }

    function freeze_owner() {
        self.AddFlag(FL_ATCONTROLS);
        self.AddCustomAttribute("no_duck", 1.0, 0.0);
        self.AddCustomAttribute("no_jump", 1.0, 0.0);
        is_frozen = true;
        target_freeze_angle = target_angle;
    }

    function unfreeze_owner() {
        self.RemoveFlag(FL_ATCONTROLS);
        self.RemoveCustomAttribute("no_duck");
        self.RemoveCustomAttribute("no_jump");
        is_frozen = false;
    }

    function reposition_target() {
        if (buttons & IN_FORWARD) {
            target_distance = min(target_distance * 1.02, PHYSGUN_FAREST_DISTANCE);
        } else if (buttons & IN_BACK) {
            target_distance = max(target_distance * 0.98, PHYSGUN_NEAREST_DISTANCE);
        }
        // Since the variable is constant when the self is frozen, get the angle directly instead
        target_freeze_angle += self.EyeAngles() - eye_angle;
        self.SnapEyeAngles(eye_angle);

        // Prevents twitching server side
        SetPropVector(self, "pl.v_angle", eye_angle + ZERO_VECTOR);

        if (buttons & IN_DUCK) {
            target_angle = snap_angle_to_multiple(target_freeze_angle, PHYSGUN_ANGLE_SNAP_MULTIPLE);
        } else {
            if (buttons_released & IN_DUCK) {
                target_freeze_angle = snap_angle_to_multiple(target_freeze_angle, PHYSGUN_ANGLE_SNAP_MULTIPLE);
            }
            target_angle = target_freeze_angle;
        }

        norm_qangle(target_angle);
        ClientPrint(self, HUD_PRINTCENTER, "ANGLES: " + target_angle.ToKVString());
    }

    function on_ressuply() {
        safe_destroy(dummy);
        safe_destroy(weapon);

        local owner_class = self.GetPlayerClass();

        if (last_class != owner_class) {
            physgun_properties = ClassPhysgunInfo[owner_class];
            reposition_world_model();

            last_class = owner_class;
        }

        recreate_weapons();

        if (force_draw_animation) {
            self.Weapon_Switch(dummy);
            force_draw_animation = false;
        } else if (is_held) {
            self.Weapon_Switch(dummy);
            run_with_delay(stop_current_sequence);
            if (active) {
                run_with_delay(@() viewmodel.ResetSequence(target
                    ? SEQ_PHYSGUN_HOLDING_ENTITY
                    : SEQ_PHYSGUN_ACTIVE));
            }
        }
    }

    function on_round_restart() {
        if (is_held) {
            is_held = false;
            force_draw_animation = true;
            stop_grabbing();
        }
    }

    function stop_current_sequence() {
        viewmodel.ResetSequence(SEQ_PHYSGUN_RESET);
        viewmodel.StopAnimation();
    }

    function destructor() {
        if (is_held) {
            self.Weapon_Switch(find_valid_weapon(self));
        }
        wearable.SetForwardVector(wearable.GetAbsVelocity());
        stop_grabbing();

        foreach (entity in [wearable, dummy, weapon, beam, viewcontrol]) {
            safe_destroy(entity);
        }

        delete self.GetScriptScope()[PHYSGUN_SCOPE_PROPERTY];
    }
}

__CollectGameEventCallbacks(::PhysgunEvents <- {
    function OnScriptHook_OnTakeDamage(params) {
        SetPropBool(params.const_entity, "m_bForcePurgeFixedupStrings", true);
        SetPropBool(params.attacker, "m_bForcePurgeFixedupStrings", true);
        // No weapon means enviromental death
        if (params.weapon) {
            return;
        }
        SetPropBool(params.weapon, "m_bForcePurgeFixedupStrings", true);

        // Do not count bosses / nextbots
        if (params.inflictor instanceof NextBotCombatCharacter) {
            return;
        }

        local victim_scope = get_scope_property_or_null(params.const_entity, PHYSINFO_SCOPE_PROPERTY);
        if (victim_scope && victim_scope.grabbed_by) {
            params.attacker = victim_scope.grabbed_by;
            return;
        }

        if (params.inflictor) {
            return;
        }
        SetPropBool(params.inflictor, "m_bForcePurgeFixedupStrings", true);

        local inflictor_scope = get_scope_property_or_null(params.inflictor, PHYSINFO_SCOPE_PROPERTY);
        if (inflictor_scope && inflictor_scope.grabbed_by) {
            params.attacker = inflictor_scope.grabbed_by;
            return;
        }
    }

    function OnGameEvent_post_inventory_application(params) {
        local player = GetPlayerFromUserID(params.userid);
        local scope = get_scope_property_or_null(player, PHYSGUN_SCOPE_PROPERTY);
        if (scope) {
            scope.on_ressuply();
        }
    }

    function OnGameEvent_player_spawn(params) {
        local player = GetPlayerFromUserID(params.userid);
        SetPropBool(player, "m_bClientSideAnimation", true);
    }

    function OnGameEvent_player_disconnect(params) {
        local player = GetPlayerFromUserID(params.userid);
        if (!player) {
            return;
        }

        local scope = get_scope_property_or_null(player, PHYSGUN_SCOPE_PROPERTY);
        if (scope) {
            scope.destructor();
        }
    }


    function OnGameEvent_player_team(params) {
        local player = GetPlayerFromUserID(params.userid);
        if (params.team != TEAM_SPECTATOR) {
            return;
        }

        local scope = get_scope_property_or_null(player, PHYSGUN_SCOPE_PROPERTY);
        if (scope) {
            scope.destructor();
            ClientPrint(player, HUD_PRINTTALK, "Physgun has been removed.");
        }
    }

    function OnGameEvent_stats_resetround(_params) {
        if (GetRoundState() != GR_STATE_PREROUND) {
            return;
        }

        for (local player; player = FindByClassname(player, "player"); ) {
            if (!player.IsAlive()) {
                continue;
            }

            local scope = get_scope_property_or_null(player, PHYSGUN_SCOPE_PROPERTY);
            if (scope) {
                scope.on_round_restart();
            }
        }
    }

    // Example usage
    function OnGameEvent_player_say(params) {
        local text = strip(params.text).tolower();
        if (text != "!physgun") {
            return;
        }

        local player = GetPlayerFromUserID(params.userid);
        local scope = get_scope_property_or_null(player, PHYSGUN_SCOPE_PROPERTY);
        if (scope) {
            scope.destructor();
            ClientPrint(player, HUD_PRINTTALK, "Physgun has been removed.");
        } else {
            PhysgunHolder(player);
            ClientPrint(player, HUD_PRINTTALK, "Physgun has been given.");
        }
    }
});

PhysgunHolder(GetListenServerHost());