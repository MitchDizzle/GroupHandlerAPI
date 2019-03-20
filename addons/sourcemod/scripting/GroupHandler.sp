#pragma semicolon 1

//Uncomment for debug messages.
#define IN_DEBUG 

//Used to make sure we don't try to add a group while the map is changing, 
// when the map finishes loading all players will fire the connect events again.
bool plCanApplyGroups[MAXPLAYERS+1];
//Stores refrences of player UserIds in this map.
// "Group A" -> [213, 244, 222]
// "Group B" -> [212, 242, 200]
//player_disconnect event is used to remove these references in order to keep a map to map order.
StringMap groupCache;

Handle hF_GroupCreated;

#define PLUGIN_VERSION "1.0.3"
public Plugin myinfo = {
    name = "Dynamic Admin Group Handler",
    author = "Mitch",
    description = "Assigns groups to players via API and makes sure they stay in that group.",
    version = PLUGIN_VERSION,
    url = "mtch.tech"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    CreateNative("GroupHandler_Register", Native_Register);
    CreateNative("GroupHandler_Unregister", Native_Unregister);
    CreateNative("GroupHandler_Assign", Native_Assign);
    CreateNative("GroupHandler_Unassign", Native_Unassign);
    hF_GroupCreated = CreateGlobalForward("GroupHandler_GroupCreated", ET_Ignore, Param_String, Param_Cell);
    RegPluginLibrary("GroupHandler");
    return APLRes_Success;
}

public void OnPluginStart() {
    //TODO: ConVars, etc.
    HookEvent("player_disconnect", EventPlayerDisconnect, EventHookMode_Pre);
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientConnected(i) && IsClientAuthorized(i)) {
            plCanApplyGroups[i] = true;
        }
    }
}

public void OnPluginEnd() {
    //Rebuild the admin cache right as we're leaving.
    delete groupCache;
    DumpAdminCache(AdminCache_Admins, true);
}

public void OnClientDisconnect(int client) {
    plCanApplyGroups[client] = false;
}

public void OnClientPostAdminCheck(int client) {
    //Let's add their groups!
    plCanApplyGroups[client] = true;
    checkPlayerGroups(client);
}

public Action EventPlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
    int userId = event.GetInt("userid");
    int client = GetClientOfUserId(userId);
    if(client <= 0 || client > MaxClients) {
        return Plugin_Continue;
    }
    //Do we have an easy way to tell if they were in one of our groups?
    AdminId adminId = getClientAdminId(client, false);
    if(adminId != INVALID_ADMIN_ID) {
        //Player has an admin Id, let's find it's groups.
        if(adminId.GroupCount <= 0) {
            //Player has no groups, IGNORE PLAYER.
            return Plugin_Continue;
        }
        char groupName[32];
        GroupId tempGroupId;
        ArrayList tempArrayList;
        int tempIndex = -1;
        for(int i = 0; i < adminId.GroupCount; i++) {
            tempGroupId = adminId.GetGroup(i, groupName, sizeof(groupName));
            if(tempGroupId == INVALID_GROUP_ID) {
                continue;
            }
            if(groupCache.GetValue(groupName, tempArrayList)) {
                //Group was in the cache, let's just remove him from all the groupCache list.
                if(tempArrayList == null || tempArrayList.Length <= 0) {
                    //Group was found, but the list is empty or not created.
                    continue;
                }
                tempIndex = tempArrayList.FindValue(userId);
                if(tempIndex > -1) {
                    //Remove the UserId from the list.
                    tempArrayList.Erase(tempIndex);
                }
            }
        }
    }
    return Plugin_Continue;
}

public void OnRebuildAdminCache(AdminCachePart part) {
    if(part == AdminCache_Admins) {
        //Added delay for any other plugin to have it's try.
        CreateTimer(0.1, Timer_RecacheGroups);
    }
}

public Action Timer_RecacheGroups(Handle timer) {
    checkGroups(); 
    return Plugin_Stop;
}

public void checkGroups() {
    if(groupCache == null) {
        return;
    }
    //Iterates the stored groups and makes sure the users saved in them are properly handled.
    char groupName[32];
    StringMapSnapshot groupCacheSnapshot = groupCache.Snapshot();
    for(int index = 0; index < groupCacheSnapshot.Length; index++) {
        groupCacheSnapshot.GetKey(index, groupName, sizeof(groupName));
        LogDebug("Checking status of Group: %s", groupName);
        checkGroup(groupName);
    }
    delete groupCacheSnapshot;
}

public void checkGroup(char[] groupName) {
    ArrayList userIdList;
    if(!groupCache.GetValue(groupName, userIdList)) {
        LogDebug("Didn't find groupName in cache: %s", groupName);
        return;
    }
    if(userIdList == null || userIdList.Length < 1) {
        //No ones there, let's escape while we can!
        LogDebug("No userIds in this list: %s", groupName);
        return;
    }
    //Get the GroupId to add to the cached players.
    GroupId groupId = INVALID_GROUP_ID;
    getAdmGroup(groupName, groupId, true);
    if(groupId == INVALID_GROUP_ID) {
        LogDebug("Unable to create or find group: %s", groupName);
        return;
    }
    
    int userId;
    int client;
    for(int i = userIdList.Length-1; i >= 0; i--) {
        userId = userIdList.Get(i);
        if(userId == -1) {
            continue;
        }
        client = GetClientOfUserId(userId);
        if(client > 0 && client <= MaxClients && IsClientConnected(client)) {
            //Assign the GroupId to the player's AdminId.
            LogDebug("Assigning: %N - %s", client, groupName);
            assignGroupId(client, getClientAdminId(client), groupId);
        } else {
            //UserId isn't valid, let's cache and remove it later.
            LogDebug("Removing: %i - %s", userId, groupName);
            userIdList.Erase(i);
        }
    }
}

public void checkPlayerGroups(int client) {
    if(groupCache == null) {
        return;
    }
    GroupId groupId;
    int userId = GetClientUserId(client);
    char groupName[32];
    ArrayList groupsToAddTo = new ArrayList();
    StringMapSnapshot groupCacheSnapshot = groupCache.Snapshot();
    for(int index = 0; index < groupCacheSnapshot.Length; index++) {
        groupCacheSnapshot.GetKey(index, groupName, sizeof(groupName));
        if(checkPlayerGroup(client, groupName, userId, groupId)) {
            groupsToAddTo.Push(groupId);
        }
    }
    delete groupCacheSnapshot;
    
    if(groupsToAddTo.Length > 0) {
        //User belongs to none, we shouldn't create an AdminId for the user.
        delete groupsToAddTo;
        return;
    }
    
    AdminId adminId = getClientAdminId(client);
    if(adminId == INVALID_ADMIN_ID) {
        LogDebug("Unable to create or find AdminId for user..");
        delete groupsToAddTo;
        return;
    }
    
    for(int i = 0; i < groupsToAddTo.Length; i++) {
        groupId = groupsToAddTo.Get(i);
        if(groupId != INVALID_GROUP_ID) {
            assignGroupId(client, adminId, groupId);
        }
    }
    delete groupsToAddTo;
}

public bool checkPlayerGroup(int client, char[] groupName, int userId, GroupId &groupId) {
    ArrayList userIdList;
    if(!groupCache.GetValue(groupName, userIdList)) {
        return false;
    }
    if(userIdList == null || userIdList.Length <= 0) {
        //No ones there, let's escape while we can!
        return false;
    }
    //Get the GroupId to add to the cached players.
    getAdmGroup(groupName, groupId, true);
    if(groupId == INVALID_GROUP_ID) {
        return false;
    }
    /*if() {
        //User is in this group, lets assign them to the admin group again.
        //assignGroupId(client, adminId, groupId);
        return true; //Return true if the player exists in this group.
    }*/
    return userIdList.FindValue(userId) != -1;
}

public bool registerGroup(char[] groupName, GroupId &groupId) {
    //Returns true if the group registered is a temp group, not in admin_groups.cfg
    if(groupCache == null) {
        groupCache = new StringMap();
    }
    bool isTemp = getAdmGroup(groupName, groupId, true);
    ArrayList tempArrayList;
    if(!groupCache.GetValue(groupName, tempArrayList)) {
        groupCache.SetValue(groupName, tempArrayList);
    }
    return isTemp;
}

public bool unregisterGroup(char[] groupName) {
    // Returns true if the group was unregistered.
    if(groupCache == null) {
        return true;
    }
    ArrayList tempArrayList;
    if(groupCache.GetValue(groupName, tempArrayList)) {
        //Group Exists, clear the players in the list.
        if(tempArrayList != null) {
            tempArrayList.Clear();
        }
        delete tempArrayList;
        return groupCache.Remove(groupName);
    }
    return true;
}

public bool assignGroup(int client, char[] groupName, bool shouldCreate) {
    AdminId adminId = getClientAdminId(client);
    if(adminId == INVALID_ADMIN_ID) {
        //Prevents adding a user to the group cache if they have issues creating an AdminId.
        LogDebug("%N unable to create adminId.", client);
        return false;
    }
    GroupId groupId = INVALID_GROUP_ID;
    getAdmGroup(groupName, groupId, shouldCreate);
    if(groupId == INVALID_GROUP_ID) {
        LogDebug("Unable to find or create group: '%s'", groupName);
        return false;
    }
    if(groupCache == null) {
        //Make sure the StringMap exists.
        groupCache = new StringMap();
    }
    ArrayList tempArrayList = null;
    groupCache.GetValue(groupName, tempArrayList);
    if(tempArrayList == null) {
        tempArrayList = new ArrayList(); //Create an ArrayList since we're adding someone to it!
        groupCache.SetValue(groupName, tempArrayList, true);
    }
    int userId = GetClientUserId(client);
    if(tempArrayList.FindValue(userId) == -1) {
        //Only add the player if they are not already in the group.
        tempArrayList.Push(GetClientUserId(client));
    }
    return assignGroupId(client, adminId, groupId);
}

public bool assignGroupId(int client, AdminId adminId, GroupId groupId) {
    if(groupId == INVALID_GROUP_ID || adminId == INVALID_ADMIN_ID) {
        return false;
    }
    // Add group to the player. Ignores the player if they are already apart of the group.
    if(!adminId.InheritGroup(groupId)) {
        // User was already apart of the group,
        LogDebug("%N was already apart of the groupId: %i", client, groupId);
        return false;
    }
    LogDebug("%N inherited the groupId: %i", client, groupId);
    return true;
}

public bool unassignGroup(int client, char[] groupName) {
    //Let's just remove the player from the cached list and worry about their admin later.
    if(groupCache == null) {
        //Nothing to remove from...
        return false;
    }
    ArrayList tempArrayList = null;
    if(groupCache.GetValue(groupName, tempArrayList)) {
        if(tempArrayList != null && tempArrayList.Length > 0) {
            //Check if the player's userId is in the list and remove it.
            int userId = GetClientOfUserId(client);
            int index = tempArrayList.FindValue(userId);
            if(index != -1) {
                tempArrayList.Erase(index);
                return true;
            }
        }
    }
    return false;
}

//Registers an Admin Group, or creates a temp one. If a temp one is created this will return True and the plugin can edit the GroupId with default values. The groupId parameter returns the GroupId found if already exists or the temp GroupId.
//GroupHandler_Register(char[] groupName, GroupId &groupId);
public int Native_Register(Handle plugin, int args) {
    char groupName[32];
    GetNativeString(1, groupName, sizeof(groupName));
    GroupId groupId = INVALID_GROUP_ID;
    bool returnVal = registerGroup(groupName, groupId);
    SetNativeCellRef(2, groupId);
    return returnVal;
}

//Unregisters any references to an Admin Group. This does not remove any admin groups from any players, use GroupHandler_Unassign() first.
//GroupHandler_Unregister(char[] groupName);
public int Native_Unregister(Handle plugin, int args) {
    char groupName[32];
    GetNativeString(1, groupName, sizeof(groupName));
    return unregisterGroup(groupName);
}

//Assigns the player to the group and retains it. Registers the group if needed.
//GroupHandler_Assign(int client, char[] groupName, bool shouldCreate = false);
public int Native_Assign(Handle plugin, int args) {
    int client = GetNativeCell(1);
    if(!NativeCheck_IsClientValid(client)) {
        return false;
    }
    char groupName[32];
    GetNativeString(2, groupName, sizeof(groupName));
    bool shouldCreate = view_as<bool>(GetNativeCell(3));
    return assignGroup(client, groupName, shouldCreate);
}

//Removes the player from the API's cache, if they had previously existed in the cache. If rebuildAdminId is true it will attempt to recreate the adminId the player uses instead of needing to rebuild the cache for one player. If you're doing this on a mass amount of players you should use DumpAdminCache(AdminCache_Groups, true). THIS FUNCTION SHOULDN'T BE USED IF THE PLAYER IS ALREADY DISCONNECTING, THAT'D BE A WASTE.
//GroupHandler_Unassign(int client, char[] groupName, bool rebuildAdminId);
public int Native_Unassign(Handle plugin, int args) {
    int client = GetNativeCell(1);
    if(!NativeCheck_IsClientValid(client)) {
        return false;
    }
    char groupName[32];
    GetNativeString(2, groupName, sizeof(groupName));
    return unassignGroup(client, groupName);
}

public bool getAdmGroup(char[] groupName, GroupId &groupId, bool shouldCreate) {
    if(findOrCreateAdmGroup(groupName, groupId, shouldCreate)) {
        // void GroupHandler_GroupCreated(char[] groupName, GroupId groupId);
        Call_StartForward(hF_GroupCreated);
        Call_PushString(groupName);
        Call_PushCell(groupId);
        Call_Finish();
        return true;
    }
    return false;
}

stock bool findOrCreateAdmGroup(char[] groupName, GroupId &groupId, bool shouldCreate = true) {
    groupId = FindAdmGroup(groupName);
    if(groupId == INVALID_GROUP_ID) {
        LogDebug("Unable to find Admin Group '%s', creating temp group instead.", groupName);
        groupId = CreateAdmGroup(groupName);
        if(groupId == INVALID_GROUP_ID) {
            //Technically shouldn't happen since we already searched, but you never know.
            LogError("Potential loop case, couldn't find or create '%s'", groupName);
            return false;
        }
        // Return true, the group was created.
        return true;
    }
    return false;
}

stock AdminId getClientAdminId(int client, bool create = true) {
    if(!plCanApplyGroups[client]) {
        //Prevent happy little accidents of assigned groups during disconnects.
        return INVALID_ADMIN_ID;
    }
    char szAuth[128];
    if(!GetClientAuthId(client, AuthId_Engine, szAuth, sizeof(szAuth))) {
        // User's steamId isn't resolving... Bad news.
        //PrintToChat(client, " Sorry, we were unable to retrieve your steamid.");
        return INVALID_ADMIN_ID;
    }
    AdminId curAdm = FindAdminByIdentity("steam", szAuth);
    if(curAdm == INVALID_ADMIN_ID && create) {
        // User isn't an admin, let's create one for them.
        curAdm = CreateAdmin();
        SetUserAdmin(client, curAdm, true);
        if(!BindAdminIdentity(curAdm, "steam", szAuth)) {
            LogError("******** %N : COULD NOT BIND TO ADMIN IDENTITY", client);
            RemoveAdmin(curAdm);
            return INVALID_ADMIN_ID;
        } else {
            //Admin Identity was bound to steamId.
            curAdm = FindAdminByIdentity("steam", szAuth);
        }
    }
    return curAdm;
}

stock LogDebug(char[] formatString, any ...) {
#if defined IN_DEBUG
    char buffer[1024];
    VFormat(buffer, sizeof(buffer), formatString, 2);
    LogMessage(buffer);
#endif
}

stock bool NativeCheck_IsClientValid(int client) {
    if(client <= 0 || client > MaxClients) {
        ThrowNativeError(SP_ERROR_NATIVE, "Client index %i is invalid", client);
        return false;
    }
    if(!IsClientConnected(client)) {
        ThrowNativeError(SP_ERROR_NATIVE, "Client %i is not connected", client);
        return false;
    }
    return true;
}