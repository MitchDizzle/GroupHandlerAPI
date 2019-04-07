#pragma semicolon 1

//Uncomment for debug messages.
#define IN_DEBUG

ArrayList groupList; //Contains a list of group names, when a new group is assigned it is added here.
ArrayList groupCache; //Contains a full list of [userId, groupIndex], 
                      // instead of creating multiple ArrayLists for each group registered, which can be a lot after a while.
// Rebuild cache happens inbetween OnMapEnd and OnMapStart, 
//  we only want to rebuild the groups only if DumpAdminCache was ran or sm_reloadadmins command was executed.
bool canCacheGroups; 

Handle hF_GroupCreated;
#define PLUGIN_VERSION "1.1.0"
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
    //TODO: What should we put here, this is a developer API..
}

public void OnPluginEnd() {
    //Rebuild the admin cache right as we're leaving.
    DumpAdminCache(AdminCache_Groups, true);
}

public void OnMapStart() {
    canCacheGroups = true;
}
public void OnMapEnd() {
    delete groupCache;
    delete groupList;
    canCacheGroups = false;
}

public void OnRebuildAdminCache(AdminCachePart part) {
    if(part == AdminCache_Admins && canCacheGroups) {
        //Added delay for any other plugin to have it's try.
        //  Some admin plugins delete the admin user first then recreate it, thanks admin_* plugins :)
        CreateTimer(0.1, Timer_RecacheGroups);
    }
}

public Action Timer_RecacheGroups(Handle timer) {
    if(groupList == null) {
        return Plugin_Stop;
    }
    //Iterate over all connected players and add only their groups.
    char groupName[32];
    int dataVal[2];
    int userId = -1;
    GroupId groupId = INVALID_GROUP_ID;
    AdminId adminId = INVALID_ADMIN_ID;
    GroupId[] tempGroupMap = new GroupId[groupList.Length];
    for(int i = 0; i < groupCache.Length; i++) {
        tempGroupMap[i] = INVALID_GROUP_ID;
    }
    for(int client = 1; client <= MaxClients; client++) {
        if(!IsClientConnected(client) || !IsClientAuthorized(client)) {
            continue;
        }
        adminId = getClientAdminId(client);
        if(adminId == INVALID_ADMIN_ID) {
            continue;
        }
        userId = GetClientUserId(client);
        for(int i = 0; i < groupCache.Length; i++) {
            groupCache.GetArray(i, dataVal, sizeof(dataVal));
            if(dataVal[0] == userId) {
                if(tempGroupMap[dataVal[1]] == INVALID_GROUP_ID) {
                    groupList.GetString(dataVal[1], groupName, sizeof(groupName));
                    getAdmGroup(groupName, groupId, true);
                    if(groupId == INVALID_GROUP_ID) {
                        continue;
                    }
                    tempGroupMap[dataVal[1]] = groupId;
                }
                assignGroupId(client, adminId, groupId);
            }
        }
    }
    return Plugin_Stop;
}

public bool registerGroup(char[] groupName, GroupId &groupId) {
    //Returns true if the group registered is a temp group, not in admin_groups.cfg
    bool isTemp = getAdmGroup(groupName, groupId, true);
    groupListAddGroupName(groupName);
    return isTemp;
}

public bool unregisterGroup(char[] groupName) {
    // Returns true if the group was unregistered.
    if(groupList == null) {
        return true;
    }
    int groupIndex = groupList.FindString(groupName);
    if(groupIndex != -1) {
        //Group Exists, clear the players in the list.
        int tempIndex;
        while((tempIndex = groupCache.FindValue(groupIndex, 1)) != -1) {
            groupCache.Erase(tempIndex);
        }
        //Grouplist is append only, removing entries will screw up entire references within groupCache
        //  Even though it leaves the name within groupList on map change everything is flushed anyways.
        //groupList.Erase(groupIndex); 
    }
    return true;
}

public bool assignGroup(int client, char[] groupName, bool shouldCreate) {
    AdminId adminId = getClientAdminId(client);
    if(adminId == INVALID_ADMIN_ID) {
        //Prevents adding a user to the group cache if they have issues creating an AdminId.
        LogDebug("%N unable to create adminId. %s/%i", client, groupName, shouldCreate);
        return false;
    }
    GroupId groupId = INVALID_GROUP_ID;
    getAdmGroup(groupName, groupId, shouldCreate);
    if(groupId == INVALID_GROUP_ID) {
        LogDebug("Unable to find or create group: '%s'", groupName);
        return false;
    }
    int groupIndex = groupListAddGroupName(groupName);
    int userId = GetClientUserId(client);
    int dataVal[2];
    if(groupCache == null) {
        groupCache = new ArrayList(2);
    }
    for(int i = 0; i <= groupCache.Length; i++) {
        if(i == groupCache.Length) {
            //UserId not in list with groupId.
            dataVal[0] = userId;
            dataVal[1] = groupIndex;
            groupCache.PushArray(dataVal, sizeof(dataVal));
            break;
        }
        groupCache.GetArray(i, dataVal, sizeof(dataVal));
        if(dataVal[0] == userId && dataVal[1] == groupIndex) {
            //Already exists in group cache.
            break;
        }
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
    if(groupList == null) {
        //Nothing to remove from...
        return false;
    }
    int groupIndex = groupListGetGroupName(groupName);
    if(groupIndex == -1) {
        //Can't find groupName cached.
        return false;
    }
    int userId = GetClientUserId(client);
    int dataVal[2];
    //Rebuild the array for fear of duplicates.
    ArrayList tempGroupCache = new ArrayList(2);
    for(int i = 0; i < groupCache.Length; i++) {
        groupCache.GetArray(i, dataVal, sizeof(dataVal));
        if(dataVal[0] != userId || dataVal[1] != groupIndex) {
            tempGroupCache.PushArray(dataVal, sizeof(dataVal));
        }
    }
    delete groupCache;
    groupCache = tempGroupCache;
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

//Rebuilds the user's admin instead of relying on DumpAdminCache() native triggering other plugins.
// One of the main issues this can't be done is that admin.cfg might be adding on a group that is also registered with this plugin.
public int Native_RebuildUserGroups(Handle plugin, int args) {
    int client = GetNativeCell(1);
    if(!NativeCheck_IsClientValid(client)) {
        return false;
    }
    return false;//rebuildUserAdmin(client);
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

public int groupListAddGroupName(char[] groupName) {
    if(groupList == null) {
        groupList = new ArrayList(ByteCountToCells(32));
    }
    int index = groupListGetGroupName(groupName);
    if(index == -1) {
        index = groupList.PushString(groupName);
    }
    return index;
}

public int groupListGetGroupName(char[] groupName) {
    if(groupList == null) {
        return -1;
    }
    return groupList.FindString(groupName);
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
        groupId.AddCommandOverride(groupName, Override_CommandGroup, Command_Allow);
        // Return true, the group was created.
        return true;
    }
    OverrideRule overrideRule;
    if(!groupId.GetCommandOverride(groupName, Override_CommandGroup, overrideRule)) {
        //Add the group name as an override if it does not exist already.
        groupId.AddCommandOverride(groupName, Override_CommandGroup, Command_Allow);
    }
    return false;
}

stock AdminId getClientAdminId(int client, bool create = true) {
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