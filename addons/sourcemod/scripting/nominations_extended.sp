/**
 * vim: set ts=4 :
 * =============================================================================
 * Nominations Extended
 * Allows players to nominate maps for Mapchooser
 *
 * Nominations Extended (C)2012-2014 Powerlord (Ross Bemrose)
 * SourceMod (C)2004-2007 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include <sourcemod>
#include "include/map_workshop_functions.inc"
#include <mapchooser>
#include "include/mapchooser_extended"
#include <colors>
#include <timer>
#include <timer-maptier>
#pragma semicolon 1

#undef REQUIRE_PLUGIN
#include <nativevotes>

#define MCE_VERSION "1.11.0 beta 4"

public Plugin:myinfo =
{
	name = "Map Nominations Extended",
	author = "Powerlord and AlliedModders LLC",
	description = "Provides Map Nominations",
	version = MCE_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
};

new Handle:g_Cvar_ExcludeOld = INVALID_HANDLE;
new Handle:g_Cvar_ExcludeCurrent = INVALID_HANDLE;

new Handle:g_Cvar_NVNextLevel = INVALID_HANDLE;
new Handle:g_Cvar_NVChangeLevel = INVALID_HANDLE;

new Handle:g_MapList = INVALID_HANDLE;
new Handle:g_MapMenu = INVALID_HANDLE;
new g_mapFileSerial = -1;

#define MAPSTATUS_ENABLED (1<<0)
#define MAPSTATUS_DISABLED (1<<1)
#define MAPSTATUS_EXCLUDE_CURRENT (1<<2)
#define MAPSTATUS_EXCLUDE_PREVIOUS (1<<3)
#define MAPSTATUS_EXCLUDE_NOMINATED (1<<4)

new Handle:g_mapTrie;

// Nominations Extended Convars
new Handle:g_Cvar_MarkCustomMaps = INVALID_HANDLE;

new bool:g_NativeVotes = false;
new bool:g_RegisteredMenusChangeLevel = false;
new bool:g_RegisteredMenusNextLevel = false;

#define NV "nativevotes"

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("nominations.phrases");
	LoadTranslations("basetriggers.phrases"); // for Next Map phrase
	LoadTranslations("mapchooser_extended.phrases");
	
	new arraySize = ByteCountToCells(PLATFORM_MAX_PATH);	
	g_MapList = CreateArray(arraySize);
	
	g_Cvar_ExcludeOld = CreateConVar("ne_excludeold", "1", "Specifies if the current map should be excluded from the Nominations list", 0, true, 0.00, true, 1.0);
	g_Cvar_ExcludeCurrent = CreateConVar("ne_excludecurrent", "1", "Specifies if the MapChooser excluded maps should also be excluded from Nominations", 0, true, 0.00, true, 1.0);
	
	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_Say);
	
	RegConsoleCmd("sm_nominate", Command_Nominate);
	
	RegAdminCmd("sm_nominate_addmap", Command_Addmap, ADMFLAG_CHANGEMAP, "sm_nominate_addmap <mapname> - Forces a map to be on the next mapvote.");
	
	// Nominations Extended cvars
	CreateConVar("ne_version", MCE_VERSION, "Nominations Extended Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_Cvar_NVChangeLevel = CreateConVar("ne_nativevotes_changelevel", "1", "TF2: Add ChangeLevel to NativeVotes 1.0 vote menu.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_NVNextLevel = CreateConVar("ne_nativevotes_nextlevel", "1", "TF2: Add NextLevel to NativeVotes 1.0 vote menu.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	HookConVarChange(g_Cvar_NVChangeLevel, Cvar_ChangeLevel);
	HookConVarChange(g_Cvar_NVNextLevel, Cvar_NextLevel);
	
	AutoExecConfig(true, "nominations_extended");
	
	g_mapTrie = CreateTrie();
}

public OnAllPluginsLoaded()
{
	if (FindPluginByFile("nominations.smx") != INVALID_HANDLE)
	{
		SetFailState("This plugin replaces nominations.  You cannot run both at once.");
	}
	
	// This is an MCE cvar... this plugin requires MCE to be loaded.  Granted, this plugin SHOULD have an MCE dependency.
	g_Cvar_MarkCustomMaps = FindConVar("mce_markcustommaps");

	g_NativeVotes = LibraryExists(NV) && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult) && GetFeatureStatus(FeatureType_Native, "NativeVotes_IsVoteCommandRegistered") == FeatureStatus_Available;
	RegisterVoteHandler();
}

public OnPluginEnd()
{
	if (g_NativeVotes)
	{
		if (g_RegisteredMenusNextLevel)
		{
			NativeVotes_UnregisterVoteCommand("NextLevel", Menu_Nominate);
		}
		
		if (g_RegisteredMenusChangeLevel)
		{
			NativeVotes_UnregisterVoteCommand("ChangeLevel", Menu_Nominate);
		}
	}
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, NV) && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult) && GetFeatureStatus(FeatureType_Native, "NativeVotes_IsVoteCommandRegistered") == FeatureStatus_Available)
	{
		g_NativeVotes = true;
		RegisterVoteHandler();
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, NV))
	{
		g_NativeVotes = false;
		g_RegisteredMenusNextLevel = false;
		g_RegisteredMenusChangeLevel = false;
	}
}

public Cvar_ChangeLevel(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (GetConVarBool(g_Cvar_NVChangeLevel))
	{
		if (!g_RegisteredMenusChangeLevel)
		{
			NativeVotes_RegisterVoteCommand("ChangeLevel", Menu_Nominate);
			g_RegisteredMenusChangeLevel = true;
		}
	}
	else
	{
		if (g_RegisteredMenusChangeLevel)
		{
			NativeVotes_UnregisterVoteCommand("ChangeLevel", Menu_Nominate);		
			g_RegisteredMenusChangeLevel = false;
		}
	}
}

public Cvar_NextLevel(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (GetConVarBool(g_Cvar_NVNextLevel))
	{
		if (!g_RegisteredMenusNextLevel)
		{
			NativeVotes_RegisterVoteCommand("NextLevel", Menu_Nominate);
			g_RegisteredMenusNextLevel = true;
		}
	}
	else
	{
		if (g_RegisteredMenusNextLevel)
		{
			NativeVotes_UnregisterVoteCommand("NextLevel", Menu_Nominate);		
			g_RegisteredMenusNextLevel = false;
		}
	}
}

RegisterVoteHandler()
{
	if (!g_NativeVotes)
		return;
		
	if (GetConVarBool(g_Cvar_NVNextLevel))
	{
		NativeVotes_RegisterVoteCommand("NextLevel", Menu_Nominate);
		g_RegisteredMenusNextLevel = true;
	}
	
	if (GetConVarBool(g_Cvar_NVChangeLevel))
	{
		NativeVotes_RegisterVoteCommand("ChangeLevel", Menu_Nominate);
		g_RegisteredMenusChangeLevel = true;
	}
}

public OnConfigsExecuted()
{
	if (ReadMapList(g_MapList,
					g_mapFileSerial,
					"nominations",
					MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER)
		== INVALID_HANDLE)
	{
		if (g_mapFileSerial == -1)
		{
			SetFailState("Unable to create a valid map list.");
		}
	}
	
	BuildMapMenu();
}

public OnMapTiersLoaded()
{
	BuildMapMenu();
}

public OnNominationRemoved(const String:map[], owner)
{
	new status;
	
	/* Is the map in our list? */
	if (!GetTrieValue(g_mapTrie, map, status))
	{
		return;	
	}
	
	/* Was the map disabled due to being nominated */
	if ((status & MAPSTATUS_EXCLUDE_NOMINATED) != MAPSTATUS_EXCLUDE_NOMINATED)
	{
		return;
	}
	
	SetTrieValue(g_mapTrie, map, MAPSTATUS_ENABLED);	
}

public Action:Command_Addmap(client, args)
{
	if (args < 1)
	{
		CReplyToCommand(client, "[NE] Usage: sm_nominate_addmap <mapname>");
		return Plugin_Handled;
	}
	
	decl String:mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));

	
	new status;
	if (!GetTrieValue(g_mapTrie, mapname, status))
	{
		CReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}
	
	new NominateResult:result = NominateMap(mapname, true, 0);
	
	if (result > Nominate_Replaced)
	{
		/* We assume already in vote is the casue because the maplist does a Map Validity check and we forced, so it can't be full */
		CReplyToCommand(client, "%t", "Map Already In Vote", mapname);
		
		return Plugin_Handled;	
	}
	
	
	SetTrieValue(g_mapTrie, mapname, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

	
	CReplyToCommand(client, "%t", "Map Inserted", mapname);
	LogAction(client, -1, "\"%L\" inserted map \"%s\".", client, mapname);

	return Plugin_Handled;		
}

public Action:Command_Say(client, args)
{
	if (!client)
	{
		return Plugin_Continue;
	}

	decl String:text[192];
	if (!GetCmdArgString(text, sizeof(text)))
	{
		return Plugin_Continue;
	}
	
	new startidx = 0;
	if(text[strlen(text)-1] == '"')
	{
		text[strlen(text)-1] = '\0';
		startidx = 1;
	}
	
	new ReplySource:old = SetCmdReplySource(SM_REPLY_TO_CHAT);
	
	if (strcmp(text[startidx], "nominate", false) == 0)
	{
		if (IsNominateAllowed(client))
		{
			AttemptNominate(client);
		}
	}
	
	SetCmdReplySource(old);
	
	return Plugin_Continue;	
}

public Action:Menu_Nominate(client, const String:voteCommand[], const String:voteArgument[], NativeVotesKickType:kickType, target)
{
	if (!client || NativeVotes_IsVoteInProgress() || !IsNominateAllowed(client, true))
	{
		return Plugin_Handled;
	}
	
	if (strlen(voteArgument) == 0)
	{
		NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_SpecifyMap);
		return Plugin_Handled;
	}
	
	new ReplySource:old = SetCmdReplySource(SM_REPLY_TO_CHAT);
	
	new Action:myReturn = Internal_NominateCommand(client, voteArgument, true);
	
	SetCmdReplySource(old);
	
	return myReturn;
}

public Action:Command_Nominate(client, args)
{
	if (!client || !IsNominateAllowed(client))
	{
		return Plugin_Handled;
	}
	
	if (args == 0)
	{
		AttemptNominate(client);
		return Plugin_Handled;
	}
	
	decl String:mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));
	
	return Internal_NominateCommand(client, mapname, false);
}

Action:Internal_NominateCommand(client, const String:mapname[], bool:isVoteMenu)
{
	new status;
	if (!GetTrieValue(g_mapTrie, mapname, status))
	{
		if (isVoteMenu && g_NativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
		}
		CReplyToCommand(client, "[NE] %t", "Map was not found", mapname);
		return Plugin_Handled;		
	}
	
	if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
	{
		if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Can't Nominate Current Map");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map in Exclude List");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;
	}
	
	new NominateResult:result = NominateMap(mapname, false, client);
	
	if (result > Nominate_Replaced)
	{
		if (result == Nominate_AlreadyInVote)
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map Already In Vote", mapname);
		}
		else
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_MapNotValid);
			}
			CReplyToCommand(client, "[NE] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;	
	}
	
	/* Map was nominated! - Disable the menu item and update the trie */
	
	SetTrieValue(g_mapTrie, mapname, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);
	
	decl String:name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	PrintToChatAll("[NE] %t", "Map Nominated", name, mapname);
	LogMessage("%s nominated %s", name, mapname);
	
	return Plugin_Handled;
}

AttemptNominate(client)
{
	SetMenuTitle(g_MapMenu, "%T", "Nominate Title", client);
	DisplayMenu(g_MapMenu, client, MENU_TIME_FOREVER);
	
	return;
}

BuildMapMenu()
{
	if (g_MapMenu != INVALID_HANDLE)
	{
		CloseHandle(g_MapMenu);
		g_MapMenu = INVALID_HANDLE;
	}
	
	ClearTrie(g_mapTrie);
	
	g_MapMenu = CreateMenu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);

	decl String:map[PLATFORM_MAX_PATH];
	
	new Handle:excludeMaps = INVALID_HANDLE;
	decl String:currentMap[PLATFORM_MAX_PATH];
	
	if (GetConVarBool(g_Cvar_ExcludeOld))
	{	
		excludeMaps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
		GetExcludeMapList(excludeMaps);
	}
	
	if (GetConVarBool(g_Cvar_ExcludeCurrent))
	{
		GetCurrentMap(currentMap, sizeof(currentMap));
	}
	
	for (new i = 0; i < GetArraySize(g_MapList); i++)
	{
		new status = MAPSTATUS_ENABLED;
		
		GetArrayString(g_MapList, i, map, sizeof(map));
		
		if (GetConVarBool(g_Cvar_ExcludeCurrent))
		{
			if (MapEqual(map, currentMap))
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_CURRENT;
			}
		}
		
		/* Dont bother with this check if the current map check passed */
		if (GetConVarBool(g_Cvar_ExcludeOld) && status == MAPSTATUS_ENABLED)
		{
			if (FindMapStringInMapArray(excludeMaps, map))
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_PREVIOUS;
			}
		}
		
		decl String:display[32], String:sMap[32];
		strcopy(sMap, sizeof(sMap), map);
		Format(display, sizeof(display), "%s [Tier:%d]", map, Timer_GetMapTier(sMap, TRACK_NORMAL));
		AddMenuItem(g_MapMenu, sMap, display);
		SetTrieValue(g_mapTrie, sMap, status);
	}
	
	SetMenuExitButton(g_MapMenu, true);

	if (excludeMaps != INVALID_HANDLE)
	{
		CloseHandle(excludeMaps);
	}
}

public Handler_MapSelectMenu(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:map[PLATFORM_MAX_PATH], String:name[MAX_NAME_LENGTH];
			GetMenuItem(menu, param2, map, sizeof(map));		
			
			GetClientName(param1, name, MAX_NAME_LENGTH);
	
			new NominateResult:result = NominateMap(map, false, param1);
			
			/* Don't need to check for InvalidMap because the menu did that already */
			if (result == Nominate_AlreadyInVote)
			{
				PrintToChat(param1, "[NE] %t", "Map Already Nominated");
				return 0;
			}
			else if (result == Nominate_VoteFull)
			{
				PrintToChat(param1, "[NE] %t", "Max Nominations");
				return 0;
			}
			
			SetTrieValue(g_mapTrie, map, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

			if (result == Nominate_Replaced)
			{
				PrintToChatAll("[NE] %t", "Map Nomination Changed", name, map);
				return 0;	
			}
			
			PrintToChatAll("[NE] %t", "Map Nominated", name, map);
			LogMessage("%s nominated %s", name, map);
		}
		
		case MenuAction_DrawItem:
		{
			decl String:map[PLATFORM_MAX_PATH];
			GetMenuItem(menu, param2, map, sizeof(map));
			
			new status;
			
			if (!GetTrieValue(g_mapTrie, map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return ITEMDRAW_DEFAULT;
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				return ITEMDRAW_DISABLED;	
			}
			
			return ITEMDRAW_DEFAULT;
		}
		
		case MenuAction_DisplayItem:
		{
			decl String:map[32];
			GetMenuItem(menu, param2, map, sizeof(map));
			
			new mark = GetConVarInt(g_Cvar_MarkCustomMaps);
			new bool:official;

			new status;
			
			if (!GetTrieValue(g_mapTrie, map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return 0;
			}
			
			decl String:buffer[100];
			decl String:display[150];
			
			if (mark)
			{
				official = IsMapOfficial(map);
			}
			
			if (mark && !official)
			{
				new tier = Timer_GetMapTier(map, TRACK_NORMAL);
				
				if(tier > 0)
				{
					switch (mark)
					{
						case 1:
						{
							Format(buffer, sizeof(buffer), "%T [Tier:%d]", "Custom Marked", param1, map, tier);
						}
						
						case 2:
						{
							Format(buffer, sizeof(buffer), "%T [Tier:%d]", "Custom", param1, map, tier);
						}
					}
				}
				else
				{
					switch (mark)
					{
						case 1:
						{
							Format(buffer, sizeof(buffer), "%T", "Custom Marked", param1, map);
						}
						
						case 2:
						{
							Format(buffer, sizeof(buffer), "%T", "Custom", param1, map);
						}
					}
				}
			}
			else
			{
				strcopy(buffer, sizeof(buffer), map);
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Current Map", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Recently Played", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Nominated", param1);
					return RedrawMenuItem(display);
				}
			}
			
			if (mark && !official)
				return RedrawMenuItem(buffer);
			
			return 0;
		}
	}
	
	return 0;
}

stock bool:IsNominateAllowed(client, bool:isVoteMenu=false)
{
	new CanNominateResult:result = CanNominate();
	
	switch(result)
	{
		case CanNominate_No_VoteInProgress:
		{
			CReplyToCommand(client, "[NE] %t", "Nextmap Voting Started");
			return false;
		}
		
		case CanNominate_No_VoteComplete:
		{
			new String:map[PLATFORM_MAX_PATH];
			GetNextMap(map, sizeof(map));
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_LevelSet);
			}
			CReplyToCommand(client, "[NE] %t", "Next Map", map);
			return false;
		}
		
		case CanNominate_No_VoteFull:
		{
			if (isVoteMenu && g_NativeVotes)
			{
				NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Generic);				
			}
			CReplyToCommand(client, "[NE] %t", "Max Nominations");
			return false;
		}
	}
	
	return true;
}