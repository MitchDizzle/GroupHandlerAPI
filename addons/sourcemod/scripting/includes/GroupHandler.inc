//Group Handler include file.

#if defined _GROUPHANDLER_included
 #endinput
#endif
#define _GROUPHANDLER_included

/**
 * Registers an Admin Group, or creates a temp one. If a temp one is created this will return True and the plugin can edit the GroupId with default values. The groupId parameter returns the GroupId found if already exists or the temp GroupId.
 *
 * @param groupName Group Name, must be unique, but doesn't have to be too unique.
 * @param groupId GroupId created or found. You can modify this, but it's probably easier to just use the GroupHandler_GroupCreated forward.
 *
 * @return true if the group registered was a temporary group created.
 */
native bool GroupHandler_Register(char[] groupName, GroupId &groupId);

/**
 * Unregisters any references to an Admin Group. This does not remove any admin groups from any players, you may want to rebuild the admin cache after this. Use DumpAdminCache(AdminCache_Groups, true) to refresh the admin flags and groups after doing this, or don't players who have the group left on them will lose it after the map changes or they leave. Should only be done sparingly.
 *
 * @param groupName Group to unregister with the handler.
 *
 * @return true if the group was unregistered.
 */
native bool GroupHandler_Unregister(char[] groupName);

/**
 * Assigns the player to the group and retains it. Registers the group if needed. If a player is already assigned to a group through other means then this will just ignore the player and not intenerally cache that player.
 *
 * @param client Client to add to the group.
 * @param groupName Group to add the client to.
 * @param shouldCreate Should the group be auto registered with the handler? This is for the lazy.
 *
 * @return true if the client was internally cached to a group.
 */
native bool GroupHandler_Assign(int client, char[] groupName, bool shouldCreate = false);

/**
 * Removes the player from the API's cache, if they had previously existed in the cache. If you're doing this on a mass amount of players you should use DumpAdminCache(AdminCache_Groups, true). THIS FUNCTION SHOULDN'T BE USED IF THE PLAYER IS ALREADY DISCONNECTING, THAT'D BE A WASTE.
 * This only removes the reference within the handler, does not actually remove the group from the client!
 *
 * @param client User who is being unassigned.
 * @param groupName Group Name the user is being removed from.
 *
 * @return
 */
native bool GroupHandler_Unassign(int client, char[] groupName);

/**
 * Called when an admin group is created because there is none within the admin_groups.cfg, allowing you to use the groupId to set default flags etc through SM's natives.
 *
 * @param groupName Name of the group created.
 * @param groupId GroupId of the just created group for you to edit.
 */
forward void GroupHandler_GroupCreated(char[] groupName, GroupId groupId);

public SharedPlugin __pl_GroupHandler = {
	name = "GroupHandler",
	file = "GroupHandler.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_GroupHandler_SetNTVOptional() {
	MarkNativeAsOptional("GroupHandler_Register");
	MarkNativeAsOptional("GroupHandler_Unregister");
	MarkNativeAsOptional("GroupHandler_Assign");
	MarkNativeAsOptional("GroupHandler_Unassign");
}
#endif
