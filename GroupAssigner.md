# GroupAssigner

Allows server operators to link player steamids to certain groups. When the player connects it will assign all the groups to them, creating if needed. This prevents needing to define all the players in admin.cfg or sourcebans.

The config allows certain server profiles (similar to Maven pom profiles). `sm_groupassigner_profile` within the `cfg/sourcemod/GroupAssigner.cfg` sets the server profile, multiple profiles are seperated by commas.

Config file is auto generated after the first load. Example listed below.

## player_groups.cfg

Contains the configuration for the GroupAssigner, located in `addons/sourcemod/configs/player_groups.cfg`

### Example with profiles set:

`sm_groupassigner_profile "Server 1,FF2"`

```c
"GroupAssigner"
{
    //Global Roles
    //Special People
	"STEAM_0:0:XXXXXXXX"    "Mitch,Veteran,Contributor"   //Mitch
    
    //Veterans
    "STEAM_0:0:YYYYYYYY"	"Respected"   //Person 1
    "STEAM_0:1:ZZZZZZZZ"	"Respected"   //Person 2
    "STEAM_0:1:AAAAAAAA"	"Respected"   //Person 3
    
    "Server 1"
    { //Server 1 profile specific roles. Appends onto any of the other active profiles and the global one.
        "STEAM_0:0:YYYYYYYY"	"Contributor"   //Abraham, made several maps for Murder (For free)
    }
    "FF2"
    {
        "STEAM_0:1:AAAAAAAA"    "Nice Guy,Contributor"  //Skibur
        "STEAM_0:1:ZZZZZZZZ"    "Contributor"  //Person 2
    }
}
```
