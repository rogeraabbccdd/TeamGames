new String:g_sTeamSkin[3][PLATFORM_MAX_PATH];
new bool:g_bTeamsLock = false;
new g_iBlickColor[3][4] = {{255, 255, 255, 90}, {255, 0, 0, 150}, {0, 0, 255, 150}};
new String:g_sRebelSound[PLATFORM_MAX_PATH];

enum OverlayStruct
{
	String:OverlayName[PLATFORM_MAX_PATH]
}
new g_Overlay[3][OverlayStruct];

public Action:Timer_HintTeam(Handle:hTimer)
{
	if (g_iNotifyPlayerTeam == 0 || g_iNotifyPlayerTeam == 4) {
		if (hTimer != INVALID_HANDLE) {
			KillTimer(hTimer);
			hTimer = INVALID_HANDLE;
		}
		return Plugin_Handled;
	}

	for (new i = 1; i <= MaxClients; i++) {
		if (!Client_IsIngame(i))
			continue;

		NotifyPlayerTeam(i, g_PlayerData[i][Team]);
	}

	return Plugin_Handled;
}

public Action:Timer_SwitchAble(Handle:hTimer, any:iClient)
{
	g_PlayerData[iClient][AbleToSwitch] = true;
	return Plugin_Handled;
}

TeamsMenu(iClient)
{
	new Handle:hMenu = CreateMenu(TeamsMenu_Handler);

	SetMenuTitle(hMenu, "%T", "MenuTeams-Title", iClient);

	AddMenuItemFormat(hMenu, "red", _, "%T", "MenuTeams-RedTeam", iClient);
	AddMenuItemFormat(hMenu, "blue", _, "%T", "MenuTeams-BlueTeam", iClient);
	AddMenuItemFormat(hMenu, "none", _, "%T", "MenuTeams-NoneTeam", iClient);
	AddMenuItem(hMenu, "spacer", "spacer", ITEMDRAW_SPACER);
	AddMenuItemFormat(hMenu, "AllNone", _, "%T", "MenuTeams-NoneTeamAll", iClient);

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, iClient, 30);
}

public TeamsMenu_Handler(Handle:hMenu, MenuAction:iAction, iClient, iKey)
{
	if (iAction == MenuAction_Select) {
		decl String:sKey[32];
		GetMenuItem(hMenu, iKey, sKey, sizeof(sKey));

		if (StrEqual(sKey, "AllNone")) {
			ClearTeams();
			TeamsMenu(iClient);
		}

		new target = GetClientAimTarget(iClient);
		if (target > 0) {
			#if defined DEBUG
			LogMessage("[TG DEBUG] Switch player %N to iTeam %d (%s).", target, _:TG_GetTeamFromString(sKey), sKey);
			#endif

			new TG_Team:iTeam = TG_GetTeamFromString(sKey);
			SwitchToTeam(iClient, target, iTeam);
		}

		TeamsMenu(iClient);
	} else if (iAction == MenuAction_Cancel && iKey == MenuCancel_ExitBack) {
		MainMenu(iClient);
	}
}

SwitchToTeam(iActivator, iClient, TG_Team:iTeam)
{
	if (iTeam == TG_ErrorTeam)
		return 5;

	if (g_bTeamsLock && iActivator >= 0)
		return 1;

	if (!Client_IsIngame(iClient) || GetClientTeam(iClient) == CS_TEAM_CT || g_PlayerData[iClient][Team] == iTeam || !TG_IsTeamValid(iTeam))
		return 4;

	if (iActivator >= 0 && !g_PlayerData[iClient][AbleToSwitch])
		return 2;

	new TG_Team:iOldTeam = g_PlayerData[iClient][Team];

	new Action:iResult = Plugin_Continue;
	Call_StartForward(Forward_OnPlayerTeam);
	Call_PushCell(iClient);
	Call_PushCell(iActivator);
	Call_PushCell(g_PlayerData[iClient][Team]);
	Call_PushCell(iTeam);
	Call_Finish(iResult);
	if (iResult != Plugin_Continue)
		return 3;

	decl String:sActivatorName[64], String:sClientName[64], String:sGameName[TG_MODULE_NAME_LENGTH];
	GetClientName(iClient, sClientName, sizeof(sClientName));

	if (Client_IsIngame(iActivator))
		GetClientName(iActivator, sActivatorName, sizeof(sActivatorName));

	if (!StrEqual(g_Game[GameID], "Core_NoGame"))
		Format(sGameName, TG_MODULE_NAME_LENGTH, "\t[%s]", g_Game[GameID]);

	if (iOldTeam == TG_NoneTeam)
		GetClientModel(iClient, g_PlayerData[iClient][DefaultModel], PLATFORM_MAX_PATH);

	g_PlayerData[iClient][Team] = iTeam;

	if (g_fChangeTeamDelay != 0.0) {
		g_PlayerData[iClient][AbleToSwitch] = false;
		CreateTimer(g_fChangeTeamDelay, Timer_SwitchAble, iClient);
	}

	Blick(iClient, iTeam);
	NotifyPlayerTeam(iClient, iTeam, false);

	if (g_iTeamDiff == 0)
		ColorPlayer(iClient, iTeam);
	else if (g_iTeamDiff == 1)
		ModelPlayer(iClient, iTeam);

	if (Client_IsIngame(iActivator)) {
		if (iTeam == TG_NoneTeam)
			CPrintToChatAll("%t", "PlayerMove-NoneTeam", sClientName);
		else if (iTeam == TG_RedTeam)
			CPrintToChatAll("%t", "PlayerMove-RedTeam", sActivatorName, sClientName);
		else if (iTeam == TG_BlueTeam)
			CPrintToChatAll("%t", "PlayerMove-BlueTeam", sActivatorName, sClientName);
	} else if (iActivator == -1 && g_Game[GameProgress] != TG_NoGame) {
		if (iTeam == TG_RedTeam)
			CPrintToChatAll("%t", "PlayerMove-RedTeam-Game", g_GameList[GetGameIndex(g_Game[GameID])][DefaultName], sClientName);
		else if (iTeam == TG_BlueTeam)
			CPrintToChatAll("%t", "PlayerMove-BlueTeam-Game", g_GameList[GetGameIndex(g_Game[GameID])][DefaultName], sClientName);
	}

	if (g_bLogCvar) {
		if (Client_IsIngame(iActivator)) {
			TG_LogRoundMessage("SetPlayerTeam", "\"%L\" moved \"%L\" to \"iTeam %d\"", iActivator, iClient, _:iTeam);
		} else {
			if (g_Game[GameProgress] != TG_NoGame)
				TG_LogGameMessage(g_Game[GameID], "SetPlayerTeam", "\"%L\" was moved to \"iTeam %d\"", iClient, _:iTeam);
			else
				TG_LogGameMessage("Core_NoGame", "SetPlayerTeam", "\"%L\" was moved to \"iTeam %d\"", iClient, _:iTeam);
		}
	}

	if (g_Game[GameProgress] != TG_NoGame && iTeam == TG_NoneTeam) {
		TG_LogGameMessage(g_Game[GameID], "PlayerLeaveGame", "\"%L\" (iTeam %d) (reason = 'ChangeTGTeam')", iClient, _:iOldTeam);

		Call_StartForward(Forward_OnPlayerLeaveGame);
		Call_PushString(g_Game[GameID]);
		Call_PushCell(iClient);
		Call_PushCell(iOldTeam);
		Call_PushCell(TG_PlayerTrigger:TG_ChangeTGTeam);
		Call_Finish();
	}

	if (TG_IsTeamRedOrBlue(iOldTeam) && GetCountPlayersInTeam(iOldTeam) == 0) {
		TG_LogGameMessage(g_Game[GameID], "OnTeamEmpty", "\"%L\" (iTeam %d) (reason = 'ChangeTGTeam')", iClient, _:iOldTeam);

		Call_StartForward(Forward_OnTeamEmpty);
		Call_PushString(g_Game[GameID]);
		Call_PushCell(iClient);
		Call_PushCell(iOldTeam);
		Call_PushCell(TG_PlayerTrigger:TG_ChangeTGTeam);
		Call_Finish();
	}

	#if defined DEBUG
	LogMessage("[TG DEBUG] Player %N switched to iTeam %d.", iClient, _:iTeam);
	#endif

	return 0;
}

ModelPlayer(iClient, TG_Team:iTeam)
{
	if (iTeam == TG_NoneTeam) {
		SetEntityModel(iClient, g_PlayerData[iClient][DefaultModel]);
	} else if (iTeam == TG_RedTeam || iTeam == TG_BlueTeam) {
		if (StrEqual(g_sTeamSkin[iTeam], "") || !IsModelPrecached(g_sTeamSkin[iTeam]))
			return 1;

		if (!FileExists(g_sTeamSkin[iTeam], false) && !FileExists(g_sTeamSkin[iTeam], true))
			return 2;

		SetEntityModel(iClient, g_sTeamSkin[iTeam]);
	}

	return 0;
}

ColorPlayer(iClient, TG_Team:iTeam)
{
	if (iTeam == TG_NoneTeam)
		DispatchKeyValue(iClient, "rendercolor", "255 255 255");
	else if (iTeam == TG_RedTeam)
		DispatchKeyValue(iClient, "rendercolor", "255 0 0");
	else if (iTeam == TG_BlueTeam)
		DispatchKeyValue(iClient, "rendercolor", "0 0 255");

	return 0;
}

Blick(iClient, TG_Team:iTeam)
{
	if (!TG_IsTeamValid(iTeam))
		return 1;

	new Handle:hFade = StartMessageOne("Fade", iClient);

	if (GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(hFade, "duration", 90);
		PbSetInt(hFade, "hold_time", 130);
		PbSetInt(hFade, "flags", (FFADE_PURGE | FFADE_IN | FFADE_STAYOUT));
		PbSetColor(hFade, "clr", g_iBlickColor[_:iTeam]);
	}
	else
	{
		BfWriteShort(hFade, 90);
		BfWriteShort(hFade, 130);
		BfWriteShort(hFade, (FFADE_PURGE | FFADE_IN | FFADE_STAYOUT));
		BfWriteByte(hFade, g_iBlickColor[_:iTeam][0]);
		BfWriteByte(hFade, g_iBlickColor[_:iTeam][1]);
		BfWriteByte(hFade, g_iBlickColor[_:iTeam][2]);
		BfWriteByte(hFade, g_iBlickColor[_:iTeam][3]);
	}

	EndMessage();

	EmitSoundToClientAny(iClient, "buttons/blip2.wav");

	return 0;
}

NotifyPlayerTeam(iClient, TG_Team:iTeam, bool:bIgnoreNoneTeam = true)
{
	if (g_iNotifyPlayerTeam == 0)
		return 1;

	if (!TG_IsTeamValid(iTeam))
		return 2;

	if (bIgnoreNoneTeam && iTeam == TG_NoneTeam)
		return 3;

	decl String:sMsg[256];

	if (iTeam == TG_NoneTeam)
		Format(sMsg, sizeof(sMsg), "%T", "TeamHud-NoneTeam", iClient);
	else if (iTeam == TG_RedTeam)
		Format(sMsg, sizeof(sMsg), "%T", "TeamHud-RedTeam", iClient);
	else if (iTeam == TG_BlueTeam)
		Format(sMsg, sizeof(sMsg), "%T", "TeamHud-BlueTeam", iClient);

	if (g_iNotifyPlayerTeam == 1) {
		PrintKeyHintText(iClient, sMsg);
	} else if (g_iNotifyPlayerTeam == 2) {
		PrintHintText(iClient, sMsg);
	} else if (g_iNotifyPlayerTeam == 3) {
		new Handle:hHudSynchronizer = CreateHudSynchronizer();

		if (hHudSynchronizer != INVALID_HANDLE) {
			if (iTeam == TG_NoneTeam)
				SetHudTextParams(-1.0, 0.85, 5.0, 200, 200, 200, 255);
			else if (iTeam == TG_RedTeam)
				SetHudTextParams(-1.0, 0.85, 5.0, 255, 0, 0, 255);
			else if (iTeam == TG_BlueTeam)
				SetHudTextParams(-1.0, 0.85, 5.0, 0, 0, 255, 255);

			ShowSyncHudText(iClient, hHudSynchronizer, sMsg);
			CloseHandle(hHudSynchronizer);
		}
	} else if (g_iNotifyPlayerTeam == 4) {
		if (iTeam == TG_NoneTeam)
			ClientCommand(iClient, "r_screenoverlay \"\"");
		else if (TG_IsTeamRedOrBlue(iTeam))
			ClientCommand(iClient, "r_screenoverlay \"%s\"", g_Overlay[iTeam][OverlayName]);
	}

	return 0;
}

ClearTeam(TG_Team:iTeam)
{
	if (!TG_IsTeamRedOrBlue(iTeam))
		return -1;

	for (new i = 1; i <= MaxClients; i++) {
		if (!Client_IsIngame(i))
			continue;

		if (g_PlayerData[i][Team] == iTeam)
			SwitchToTeam(-1, i, TG_NoneTeam);
	}

	return 0;
}

ClearTeams()
{
	ClearTeam(TG_RedTeam);
	ClearTeam(TG_BlueTeam);
}

bool:MakeRebel(iClient)
{
	new Action:iResult = Plugin_Continue;
	Call_StartForward(Forward_OnPlayerRebel);
	Call_PushCell(iClient);
	Call_PushCell(TG_GetPlayerTeam(iClient));
	Call_Finish(iResult);
	if (iResult != Plugin_Continue)
		return false;

	if (g_Game[GameProgress] == TG_InPreparation || g_Game[GameProgress] == TG_InProgress)
		PlayerEquipmentLoad(iClient);

	new TG_Team:iOldTeam = TG_GetPlayerTeam(iClient);
	ChangeRebelStatus(iClient, true);
	SwitchToTeam(-1, iClient, TG_NoneTeam);

	decl String:sName[TG_MODULE_NAME_LENGTH];
	GetClientName(iClient, sName, sizeof(sName));
	CPrintToChatAll("%t", "Rebel-Become", sName);

	if (g_sRebelSound[0] != '\0' && IsSoundPrecached(g_sRebelSound))
		EmitSoundToAllAny(g_sRebelSound);

	if (g_Game[GameProgress] != TG_NoGame) {
		TG_LogGameMessage(g_Game[GameID], "PlayerLeaveGame", "\"%L\" (iTeam %d) (reason = 'Rebel')", iClient, _:iOldTeam);

		Call_StartForward(Forward_OnPlayerLeaveGame);
		Call_PushString(g_Game[GameID]);
		Call_PushCell(iClient);
		Call_PushCell(g_PlayerData[iClient][Team]);
		Call_PushCell(TG_PlayerTrigger:TG_Rebel);
		Call_Finish();
	}

	if (TG_IsTeamRedOrBlue(iOldTeam) && GetCountPlayersInTeam(iOldTeam) == 0) {
		TG_LogGameMessage(g_Game[GameID], "OnTeamEmpty", "\"%L\" (iTeam %d) (reason = 'Rebel')", iClient, _:iOldTeam);

		Call_StartForward(Forward_OnTeamEmpty);
		Call_PushString(g_Game[GameID]);
		Call_PushCell(iClient);
		Call_PushCell(iOldTeam);
		Call_PushCell(TG_PlayerTrigger:TG_Rebel);
		Call_Finish();
	}

	return true;
}

stock bool:PrintKeyHintText(client, const String:format[], any:...)
{
	new Handle:userMessage = StartMessageOne("KeyHintText", client);

	if (userMessage == INVALID_HANDLE) {
		return false;
	}

	decl String:buffer[1024];

	SetGlobalTransTarget(client);
	VFormat(buffer, sizeof(buffer), format, 3);

	if (GetUserMessageType() == UM_Protobuf)
	{
		PbAddString(userMessage, "hints", buffer);
	}
	else
	{
		BfWriteByte(userMessage, 1);
		BfWriteString(userMessage, buffer);
	}

	EndMessage();

	return true;
}
