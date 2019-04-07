# GroupHandlerAPI
Allows plugins to easily assign admin groups to players. Makes creating VIP plugins easier because you don't need to worry about setting players flags or colliding with other plugins that may do the same.

Right now there's no easy way to tell if a player belongs to a certain group. I'm not sure if this is a feature people would care about to have, since the plugin that uses this should track wether or not they want to add a certain player to a group or not, and not rely on this system for that. Currently in SM removing groups from an admin identity is not possible through their API so a rebuild admin cache (sm_reloadadmins) will be needed to regenerate groups.

# GroupAssigner

[More documentation can be found here for the sub plugin GroupAssigner](./GroupAssigner.md)

## GroupHandler Example:

Essentially all the plugin has to do is:

```c++
char myGroupNames[5][] = {
    "Group #1",
    "Group #2",
    "Group #3",
    "Group #4",
    "Cool Group"
};

public void OnClientPostAdminCheck(int client) {
    int groupNum = 1; // * Does some kind of awesome calls to some kind of database some where to set this *
    
    //Only assigns the player to this group if it exists, wont create the group.
    // Be warned though, if you're creating the group within your plugin then assign the player it'll stick.
    // So make sure that you use the forward for whenever a new group is created instead.
    GroupHandler_Assign(client, myGroupNames[0], false); 
    
    //Assign the player to the group
    if(groupNum >= 0 && groupNum < 5) {
        //Only add in if the groupNum
        GroupHandler_Assign(client, myGroupNames[groupNum]); 
    }
}

public void GroupHandler_GroupCreated(char[] groupName, GroupId groupId) {
    //Called if the group wasn't found and was created as a temp group
    
    if(StrEqual(groupName, "Cool Group")) {
        groupId.SetFlag(Admin_Custom4, true);
    }
}
```
