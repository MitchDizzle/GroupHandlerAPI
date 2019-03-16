# GroupHandlerAPI
Allows plugins to easily assign admin groups to players. Makes creating VIP plugins easier because you don't need to worry about setting players flags or colliding with other plugins that may do the same.

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
    
    //Assign the player to the group
    if(groupNum >= 0 && groupNum < 5) {
        //Only add in if the groupNum
        GroupHandler_Assign(client, myGroupNames[groupNum], true);
    }
}

public void GroupHandler_GroupCreated(char[] groupName, GroupId groupId) {
    //Called if the group wasn't found and was created as a temp group
    
    if(StrEqual(groupName, "Cool Group")) {
        groupId.SetFlag(Admin_Custom4, true);
    }
}
```
