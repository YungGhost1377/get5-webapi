/**
 * =============================================================================
 * Get5 web API integration
 * Copyright (C) 2016. Sean Lewis.  All rights reserved.
 * =============================================================================
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "include/get5.inc"
#include "include/logdebug.inc"
#include <cstrike>
#include <sourcemod>

#include "get5/util.sp"

#include <ripext>

#pragma semicolon 1
#pragma newdecls required

int g_MatchID = -1;
ConVar g_UseSVGCvar;
char g_LogoBasePath[128];
ConVar g_APIKeyCvar;
char g_APIKey[128];

ConVar g_APIURLCvar;
char g_APIURL[128];

char g_storedAPIURL[128];
char g_storedAPIKey[128];

ConVar g_EnableDemoUpload;

#define LOGO_DIR "materials/panorama/images/tournaments/teams"
#define LEGACY_LOGO_DIR "resource/flash/econ/tournaments/teams"

// clang-format off
public Plugin myinfo = {
  name = "Get5 API Integration - RIPEXT",
  author = "splewis/phlexplexico",
  description = "Records match stats to G5API.",
  version = "2.0",
  url = "https://github.com/phlexplexico/get5-web"
};
// clang-format on

public void OnPluginStart() {
  InitDebugLog("get5_debug", "get5_api");
  LogDebug("OnPluginStart version=2.0");
  g_UseSVGCvar = CreateConVar("get5_use_svg", "0", "support svg team logos");
  HookConVarChange(g_UseSVGCvar, LogoBasePathChanged);
  g_LogoBasePath = g_UseSVGCvar.BoolValue ? LOGO_DIR : LEGACY_LOGO_DIR;

  g_EnableDemoUpload = CreateConVar("get5_upload_demos", "0", "Upload demo on post match.");

  g_APIKeyCvar =
      CreateConVar("get5_web_api_key", "", "Match API key, this is automatically set through rcon", FCVAR_DONTRECORD);
  HookConVarChange(g_APIKeyCvar, ApiInfoChanged);

  g_APIURLCvar = CreateConVar("get5_web_api_url", "", "URL the get5 api is hosted at.", FCVAR_DONTRECORD);

  HookConVarChange(g_APIURLCvar, ApiInfoChanged);

  RegConsoleCmd("get5_web_avaliable",
                Command_Avaliable);  // legacy version since I'm bad at spelling
  RegConsoleCmd("get5_web_available", Command_Avaliable);
  /** Create and exec plugin's configuration file **/
  
}

public Action Command_Avaliable(int client, int args) {
  char versionString[64] = "unknown";
  ConVar versionCvar = FindConVar("get5_version");
  if (versionCvar != null) {
    versionCvar.GetString(versionString, sizeof(versionString));
  }

  JSONObject json = new JSONObject();

  json.SetInt("gamestate", view_as<int>(Get5_GetGameState()));
  json.SetInt("available", 1);
  json.SetString("plugin_version", versionString);

  char buffer[256];
  json.ToString(buffer, sizeof(buffer), true);
  ReplyToCommand(client, buffer);

  delete json;

  return Plugin_Handled;
}

public void LogoBasePathChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  g_LogoBasePath = g_UseSVGCvar.BoolValue ? LOGO_DIR : LEGACY_LOGO_DIR;
}

public void ApiInfoChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  g_APIKeyCvar.GetString(g_APIKey, sizeof(g_APIKey));
  g_APIURLCvar.GetString(g_APIURL, sizeof(g_APIURL));

  // Add a trailing backslash to the api url if one is missing.
  int len = strlen(g_APIURL);
  if (len > 0 && g_APIURL[len - 1] != '/') {
    StrCat(g_APIURL, sizeof(g_APIURL), "/");
  }

  LogDebug("get5_web_api_url now set to %s", g_APIURL);
}

static HTTPClient CreateRequest(const char[] apiMethod, any:...) {
  char url[1024];
  Format(url, sizeof(url), "%s%s", g_APIURL, apiMethod);
  LogDebug("Our URL is: %s", url);
  char formattedUrl[1024];
  VFormat(formattedUrl, sizeof(formattedUrl), url, 2);

  LogDebug("Trying to create request to url %s", formattedUrl);

  HTTPClient req = new HTTPClient(formattedUrl);
  if (StrEqual(g_APIKey, "")) {
    // Not using a web interface.
    return null;
  } else if (req == INVALID_HANDLE) {
    LogError("Failed to create request to %s", formattedUrl);
    return null;
  } else {
    return req;
  }
}

static HTTPClient CreateDemoRequest(const char[] apiMethod, any:...) {
  char url[1024];
  Format(url, sizeof(url), "%s%s", g_storedAPIURL, apiMethod);
  LogDebug("Our URL is: %s", url);
  char formattedUrl[1024];
  VFormat(formattedUrl, sizeof(formattedUrl), url, 2);

  LogDebug("Trying to create request to url %s", formattedUrl);

  HTTPClient req = new HTTPClient(formattedUrl);
  if (StrEqual(g_storedAPIKey, "")) {
    // Not using a web interface.
    return null;
  } else if (req == INVALID_HANDLE) {
    LogError("Failed to create request to %s", formattedUrl);
    return null;
  } else {
    return req;
  }
}

public void RequestCallback(HTTPResponse response, any value) {
    if (response.Status == HTTPStatus_InternalServerError) {
        LogError("[ERR] API request failed, HTTP status code: %d", response.Status);
        char sData[1024];
        response.Data.ToString(sData, sizeof(sData), JSON_INDENT(4));
        LogError("[ERR] Response:\n%s", sData);
        return;
    } 
}

void OnDemoUploaded(HTTPStatus status, any value)
{
  if (status != HTTPStatus_OK) {
      LogError("[ERR] Demo request failed, HTTP status code: %d", status);
      return;
  }
}  

public void Get5_OnBackupRestore() {
  char matchid[64];
  Get5_GetMatchID(matchid, sizeof(matchid));
  g_MatchID = StringToInt(matchid);
}

public void Get5_OnSeriesInit() {
  char matchid[64];
  Get5_GetMatchID(matchid, sizeof(matchid));
  g_MatchID = StringToInt(matchid);

  // Handle new logos.
  if (!DirExists(g_LogoBasePath)) {
    if (!CreateDirectory(g_LogoBasePath, 755)) {
      LogError("Failed to create logo directory: %s", g_LogoBasePath);
    }
  }

  char logo1[32];
  char logo2[32];
  GetConVarStringSafe("mp_teamlogo_1", logo1, sizeof(logo1));
  GetConVarStringSafe("mp_teamlogo_2", logo2, sizeof(logo2));
  CheckForLogo(logo1);
  CheckForLogo(logo2);
}

public void CheckForLogo(const char[] logo) {
  if (StrEqual(logo, "")) {
    return;
  }

  char logoPath[PLATFORM_MAX_PATH];
  // change png to svg because it's better supported
  if (g_UseSVGCvar.BoolValue) {
    Format(logoPath, sizeof(logoPath), "%s/%s.svg", g_LogoBasePath, logo);
  } else {
    Format(logoPath, sizeof(logoPath), "%s/%s.png", g_LogoBasePath, logo);
  }

  // Try to fetch the file if we don't have it.
  if (!FileExists(logoPath)) {
    LogDebug("Fetching logo for %s", logo);
    HTTPClient req = g_UseSVGCvar.BoolValue
                     ? CreateRequest("/static/img/logos/%s.svg", logo)
                     : CreateRequest("/static/img/logos/%s.png", logo);

    if (req == null) {
      return;
    }
    req.DownloadFile("", logoPath, LogoCallback);
    LogMessage("Saved logo for %s at %s", logo, logoPath);
  }
}

public void LogoCallback(HTTPStatus status, any value) {
  if (status != HTTPStatus_OK) {
    LogError("Logo request failed, status code = %d", status);
    return;
  }
  return;
}

public void Get5_OnGoingLive(int mapNumber) {
  char mapName[64];
  
  GetCurrentMap(mapName, sizeof(mapName));
  HTTPClient req = CreateRequest("match/%d/map/%d/start", g_MatchID, mapNumber);
  JSONObject mtchDetail = new JSONObject();
  if (req != null) {
    mtchDetail.SetString("key", g_APIKey);
    mtchDetail.SetString("mapname", mapName);
    req.Post("", mtchDetail, RequestCallback);
  }
  // Store Cvar since it gets reset after match finishes?
  if (g_EnableDemoUpload.BoolValue) {
    Format(g_storedAPIKey, sizeof(g_storedAPIKey), g_APIKey);
    Format(g_storedAPIURL, sizeof(g_storedAPIURL), g_APIURL);
  }
  Get5_AddLiveCvar("get5_web_api_key", g_APIKey);
  Get5_AddLiveCvar("get5_web_api_url", g_APIURL);
  delete mtchDetail;
}

public void UpdateRoundStats(int mapNumber) {
  int team1Score = CS_GetTeamScore(Get5_MatchTeamToCSTeam(MatchTeam_Team1));
  int team2Score = CS_GetTeamScore(Get5_MatchTeamToCSTeam(MatchTeam_Team2));

  HTTPClient req = CreateRequest("match/%d/map/%d/update", g_MatchID, mapNumber);
  JSONObject rndStat = new JSONObject();
  if (req != null) {
    rndStat.SetString("key", g_APIKey);
    rndStat.SetInt("team1score", team1Score);
    rndStat.SetInt("team2score", team2Score);
    req.Post("", rndStat, RequestCallback);
  }

  KeyValues kv = new KeyValues("Stats");
  Get5_GetMatchStats(kv);
  char mapKey[32];
  Format(mapKey, sizeof(mapKey), "map%d", mapNumber);
  if (kv.JumpToKey(mapKey)) {
    if (kv.JumpToKey("team1")) {
      UpdatePlayerStats(kv, MatchTeam_Team1);
      kv.GoBack();
    }
    if (kv.JumpToKey("team2")) {
      UpdatePlayerStats(kv, MatchTeam_Team2);
      kv.GoBack();
    }
    kv.GoBack();
  }
  delete kv;
  delete rndStat;
}

public void Get5_OnMapResult(const char[] map, MatchTeam mapWinner, int team1Score, int team2Score,
                      int mapNumber) {
  char winnerString[64];
  GetTeamString(mapWinner, winnerString, sizeof(winnerString));

  HTTPClient req = CreateRequest("match/%d/map/%d/finish", g_MatchID, mapNumber);
  JSONObject mtchRes = new JSONObject();
  if (req != null && mapNumber > -1) {
    mtchRes.SetString("key", g_APIKey);
    mtchRes.SetInt("team1score", team1Score);
    mtchRes.SetInt("team2score", team2Score);
    mtchRes.SetString("winner", winnerString);
    req.Post("", mtchRes, RequestCallback);
  }
  delete mtchRes;
}

public void UpdatePlayerStats(KeyValues kv, MatchTeam team) {
  char name[MAX_NAME_LENGTH];
  char auth[AUTH_LENGTH];
  int mapNumber = MapNumber();

  if (kv.GotoFirstSubKey()) {
    JSONObject pStat = new JSONObject();
    pStat.SetString("key", g_APIKey);
    do {
      kv.GetSectionName(auth, sizeof(auth));
      kv.GetString("name", name, sizeof(name));
      char teamString[16];
      GetTeamString(team, teamString, sizeof(teamString));

      HTTPClient req = CreateRequest("match/%d/map/%d/player/%s/update", g_MatchID,
                                 mapNumber, auth);
      if (req != null) {
        pStat.SetString("team", teamString);
        pStat.SetString("name", name);
        pStat.SetInt(STAT_KILLS, kv.GetNum(STAT_KILLS));
        pStat.SetInt(STAT_DEATHS, kv.GetNum(STAT_DEATHS));
        pStat.SetInt(STAT_ASSISTS, kv.GetNum(STAT_ASSISTS));
        pStat.SetInt(STAT_FLASHBANG_ASSISTS, kv.GetNum(STAT_FLASHBANG_ASSISTS));
        pStat.SetInt(STAT_TEAMKILLS, kv.GetNum(STAT_TEAMKILLS));
        pStat.SetInt(STAT_SUICIDES, kv.GetNum(STAT_SUICIDES));
        pStat.SetInt(STAT_DAMAGE, kv.GetNum(STAT_DAMAGE));
        pStat.SetInt(STAT_HEADSHOT_KILLS, kv.GetNum(STAT_HEADSHOT_KILLS));
        pStat.SetInt(STAT_ROUNDSPLAYED, kv.GetNum(STAT_ROUNDSPLAYED));
        pStat.SetInt(STAT_BOMBPLANTS, kv.GetNum(STAT_BOMBPLANTS));
        pStat.SetInt(STAT_BOMBDEFUSES, kv.GetNum(STAT_BOMBDEFUSES));
        pStat.SetInt(STAT_1K, kv.GetNum(STAT_1K));
        pStat.SetInt(STAT_2K, kv.GetNum(STAT_2K));
        pStat.SetInt(STAT_3K, kv.GetNum(STAT_3K));
        pStat.SetInt(STAT_4K, kv.GetNum(STAT_4K));
        pStat.SetInt(STAT_5K, kv.GetNum(STAT_5K));
        pStat.SetInt(STAT_V1, kv.GetNum(STAT_V1));
        pStat.SetInt(STAT_V2, kv.GetNum(STAT_V2));
        pStat.SetInt(STAT_V3, kv.GetNum(STAT_V3));
        pStat.SetInt(STAT_V4, kv.GetNum(STAT_V4));
        pStat.SetInt(STAT_V5, kv.GetNum(STAT_V5));
        pStat.SetInt(STAT_FIRSTKILL_T, kv.GetNum(STAT_FIRSTKILL_T));
        pStat.SetInt(STAT_FIRSTKILL_CT, kv.GetNum(STAT_FIRSTKILL_CT));
        pStat.SetInt(STAT_FIRSTDEATH_T, kv.GetNum(STAT_FIRSTDEATH_T));
        pStat.SetInt(STAT_FIRSTDEATH_CT, kv.GetNum(STAT_FIRSTDEATH_CT));
        pStat.SetInt(STAT_TRADEKILL, kv.GetNum(STAT_TRADEKILL));
        pStat.SetInt(STAT_KAST, kv.GetNum(STAT_KAST));
        pStat.SetInt(STAT_CONTRIBUTION_SCORE, kv.GetNum(STAT_CONTRIBUTION_SCORE));
        req.Post("", pStat, RequestCallback);
      }
    } while (kv.GotoNextKey());
    kv.GoBack();
    delete pStat;
  } 
}

public void Get5_OnMapVetoed(MatchTeam team, const char[] map){
  char teamString[64];
  GetTeamString(team, teamString, sizeof(teamString));
  LogDebug("Map Veto START team %s map vetoed %s", team, map);
  HTTPClient req = CreateRequest("match/%d/vetoUpdate", g_MatchID);
  JSONObject vetoData = new JSONObject();
  if (req != null) {
    vetoData.SetString("key", g_APIKey);
    vetoData.SetString("map", map);
    vetoData.SetString("teamString", teamString);
    vetoData.SetString("pick_or_veto", "ban");  
    req.Post("", vetoData, RequestCallback);
  }
  LogDebug("Accepted Map Veto.");
  delete vetoData;
}

public void Get5_OnDemoFinished(const char[] filename){
  if (g_EnableDemoUpload.BoolValue) {
    LogDebug("About to enter UploadDemo. SO YES WE ARE.");
    int mapNumber = MapNumber();
    HTTPClient req = CreateDemoRequest("match/%d/map/%d/demo", g_MatchID, mapNumber-1);
    JSONObject demoJSON = new JSONObject();
    LogDebug("Our api url: %s", g_storedAPIURL);
    // Send URL to store in database to show users at end of match.
    // This requires anonmyous downloads on the FTP server unless
    // you give out usernames.
    if (req != null) {
      demoJSON.SetString("key", g_storedAPIKey);
      LogDebug("Our demo string: %s", filename);
      demoJSON.SetString("demoFile", filename);
      req.Post("", demoJSON, RequestCallback);

      req = CreateDemoRequest("match/%d/map/%d/demo/upload/%s", g_MatchID, mapNumber-1, g_storedAPIKey);
      if (req != null) {
        LogDebug("Uploading demo to server...");
        req.UploadFile("", filename, OnDemoUploaded);
        LogDebug("COMPLETE!");
      }
    }

    // Need to store as get5 recycles the configs before the demos finish recording.
    Format(g_storedAPIKey, sizeof(g_storedAPIKey), "");
    Format(g_storedAPIURL, sizeof(g_storedAPIURL), "");
    delete demoJSON;
  }
}

public void Get5_OnMapPicked(MatchTeam team, const char[] map){
  LogDebug("Accepted Map Pick.");
  char teamString[64];
  GetTeamString(team, teamString, sizeof(teamString));
  LogDebug("Map Pick START team %s map vetoed %s", team, map);
  HTTPClient req = CreateRequest("match/%d/vetoUpdate", g_MatchID);
  JSONObject vetoData = new JSONObject();
  if (req != null) {
    vetoData.SetString("key", g_APIKey);
    vetoData.SetString("map", map);
    vetoData.SetString("teamString", teamString);
    vetoData.SetString("pick_or_veto", "pick");
    req.Post("", vetoData, RequestCallback);
  }
  LogDebug("Accepted Map Pick.");
  delete vetoData;
}

public void Get5_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore) {
  char winnerString[64];
  GetTeamString(seriesWinner, winnerString, sizeof(winnerString));

  KeyValues kv = new KeyValues("Stats");
  Get5_GetMatchStats(kv);
  bool forfeit = kv.GetNum(STAT_SERIES_FORFEIT, 0) != 0;
  delete kv;

  HTTPClient req = CreateRequest("match/%d/finish", g_MatchID);
  JSONObject seriesRes = new JSONObject();
  if (req != null) {
    seriesRes.SetString("key", g_APIKey);
    seriesRes.SetString("winner", winnerString);
    seriesRes.SetInt("team1score", team1MapScore);
    seriesRes.SetInt("team2score", team2MapScore);
    seriesRes.SetInt("forfeit", forfeit);
    req.Post("", seriesRes, RequestCallback);
  }
  g_APIKeyCvar.SetString("");
  delete seriesRes;
}

public void Get5_OnRoundStatsUpdated() {
  if (Get5_GetGameState() == Get5State_Live) {
    UpdateRoundStats(MapNumber());
  }
}

static int MapNumber() {
  int t1, t2, n;
  int buf;
  Get5_GetTeamScores(MatchTeam_Team1, t1, buf);
  Get5_GetTeamScores(MatchTeam_Team2, t2, buf);
  Get5_GetTeamScores(MatchTeam_TeamNone, n, buf);
  return t1 + t2 + n;
}
