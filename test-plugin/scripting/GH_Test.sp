/**


    This plugin is for testing purposes, not needed for core functionality.


**/
#pragma semicolon 1

#include <GroupHandler>

char testGroupName[32];

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
    name = "Group Handler Test Plugin",
    author = "Mitch",
    description = "Simple test plugin for the groups, will give user Custom4 flag until he disconnects.",
    version = PLUGIN_VERSION,
    url = "mtch.tech"
};


public void OnPluginStart() {
    RegAdminCmd("sm_assign", Command_Assign, 0);
    Format(testGroupName, sizeof(testGroupName), "GT Test - %i", GetRandomInt(0,100));
}

public Action Command_Assign(int client, int args) {
    if(!client) {
        return Plugin_Handled;
    }
    ReplyToCommand(client, "Adding you to: %s (%i)", testGroupName, GroupHandler_Assign(client, testGroupName));
    return Plugin_Handled;
}

public void GroupHandler_GroupCreated(char[] groupName, GroupId groupId) {
    //Called if the group wasn't found and was created as a temp group
    if(StrEqual(groupName, testGroupName)) {
        PrintToServer("Group Created: %s", groupName);
        groupId.SetFlag(Admin_Custom4, true);
    }
}

