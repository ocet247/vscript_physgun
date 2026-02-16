# VScript Physgun
Recreates physgun in games that don't have it by using vscript. Made for Team Fortress 2 but might work in other games.

## Usage
To give player a physgun, pass them as a parameter into `PhysgunHolder` class. To remove it, search for `PHYSGUN_SCOPE_PROPERTY` variable inside their scope and call `.destructor()` method on it.

The physgun can operate in 2 modes:
* Velocity mode: moves the target by changing their velocity which allows the user to accelerate the target.
* Noclip mode: moves the target by changing their position which allows them to pass through blocks.

Physgun allows to lenghten or shorten the beam.

It's possible to rotate the target by using mouse.

The target can also be freezed after releasing it which prevents movement for most entities.

Any fall damage dealt while the target is held or released no later than 3 seconds ago will count towards the physgun user, giving them a kill/assist.

## Controls
* Hold primary attack (default: left click) in order to grab a target, in case the target is not found the beam will stay active until one is found.
* Release the primary attack to release the target or stop searching for one.
* Press secondary attack (default: right click) with no target to toggle velocity and noclip modes.
* Press secondary attack with target present to freeze it.
* Press reload (default: R) with a target present to enter beam modification state. In this state the following controls hold:
  * Forward (defualt: W) to lengthen the beam.
  * Backward (default: S) to shorten the beam.
  * Move your mouse in order to rotate the target, crouch (default: Ctrl) can be pressed in order to restrict the increments to be divisable by 45 (e.g. only allow the target to be at 45, 90, 135 degrees etc).

## Known issues
* When in beam modification state, the target slightly moves without any mouse movement present.
* Beam doesn't stick to the physgun perfectly when moving, this is a limitation of `env_quadraticbeam` entity.
