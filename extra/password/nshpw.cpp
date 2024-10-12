/* Copyright Nash!Com - Daniel Nashed Communication Systems, 2024 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <time.h>


uid_t g_uid  = getuid();
gid_t g_gid  = getgid();
uid_t g_euid = geteuid();
gid_t g_egid = getegid();


bool begins (const char *pszBuffer, const char *pszMatch)
{
    const char *pFound = NULL;

    if (NULL == pszBuffer)
        return false;

    if (NULL == pszMatch)
        return false;

    pFound = strstr (pszBuffer, pszMatch);

    if (NULL == pFound)
        return false;

    if (pFound != pszBuffer)
        return false;

    return true;
}


int SwitchUser (uid_t new_uid, gid_t new_gid, bool bSetEnv)
{
    uid_t uid  = getuid();
    gid_t gid  = getgid();
    uid_t euid = geteuid();
    gid_t egid = getegid();

    int upd = 0;

    struct passwd *pPasswd = NULL;

    if ((new_gid != gid) || (new_gid != egid))
    {
        if (setregid (new_gid, new_gid))
        {
            perror ("Failed to switch group\n");
            return 1;
        }

        upd++;
    }

    if ((new_uid != uid) || (new_uid != euid))
    {
        if (setreuid (new_uid, new_uid))
        {
            perror ("Failed to switch user\n");
            return 1;
        }

        upd++;
    }

    if (0 == upd)
        return 0;

    if (false == bSetEnv)
        return 0;

    pPasswd = getpwuid (euid);

    if (NULL == pPasswd)
        return 1;

    if (pPasswd->pw_name)
    {
        setenv ("USER",   pPasswd->pw_name, 1);
        setenv ("LOGNAME", pPasswd->pw_name, 1);
    }

    if (pPasswd->pw_dir)
    {
        setenv ("HOME", pPasswd->pw_dir, 1);
    }

    return 0;
}


int SwitchToUser (bool bSetEnv)
{
    return SwitchUser (g_uid, g_gid, bSetEnv);
}


int SwitchToRealUser (bool bSetEnv)
{
    return SwitchUser (g_euid, g_egid, bSetEnv);
}


int GetTimeString (time_t *pTime, char *pszTime, size_t MaxBuffer)
{
    int ret = 0;
    struct tm TimeTM = {0};

    localtime_r (pTime, &TimeTM);

    // strftime (pszTime, MaxBuffer, "%a, %b %d %Y %H:%M:%S", &TimeTM);
    strftime (pszTime, MaxBuffer, "%Y.%m.%d %H:%M:%S", &TimeTM);

    return ret;
}


int main (int argc, char *argv[0])
{
    int     ret     = 0;
    FILE    *fpLog  = NULL;
    FILE    *fpPwd  = NULL;
    ssize_t len     = 0;
    size_t  LineLen = 4096;
    pid_t   ppid    = getppid();
    time_t  tNow    = {0};

    char szProc[4096]    = {0};
    char szProcess[4096] = {0};
    char szNow[100]      = {0};
    char *pLine          = NULL;
    char *p              = NULL;
    char *pszNow         = NULL;

    time (&tNow);
    GetTimeString (&tNow, szNow, sizeof (szNow));

    fpLog = fopen ("/tmp/nshpw.log", "a");

    if (NULL == fpLog)
    {
        perror ("Cannot open log file");
	ret = 1;
        goto Done;
    }

    /* First open password file with vault user */
    fpPwd = fopen ("/home/vault/password.txt", "r");

    if (NULL == fpPwd)
    {
        perror ("Cannot open password file");
        fprintf (fpLog, "%s Cannot open password file for request: [%s] (%u)\n", szNow, szProcess, ppid);
        ret = 4;
        goto Done;
    }

    /* Switch to user to be able to read exe link */
    SwitchToUser (false);

    snprintf (szProc, sizeof (szProc), "/proc/%u/exe", ppid);
    len = readlink (szProc, szProcess, sizeof (szProcess));

    if (len <= 0)
    {
	perror ("Cannot get process name for pid");
        fprintf (fpLog, "%s Cannot get process name for pid: %u\n", szNow, ppid);
        ret = 2;
        goto Done;
    }

    if (!begins (szProcess, "/opt/hcl/domino/notes"))
    {    
        fprintf (fpLog, "%s Unauthorized binary: [%s] (%u)\n", szNow, szProcess, ppid);
	ret = 3;
	goto Done;
    }

    /* Read password only if matching process */
    pLine = (char *) malloc (LineLen);

    if (NULL == pLine)
    {
        perror ("Cannot allocate memory");
        fprintf (fpLog, "%s Cannot cannot allocate memory for request: [%s] (%u)\n", szNow, szProcess, ppid);
        ret = 5;
        goto Done;
    }

    len = getline (&pLine, &LineLen, fpPwd);

    if (len <= 0)
    {
        perror ("Cannot read password");
        fprintf (fpLog, "%s Cannot read password for request: [%s] (%u)\n", szNow, szProcess, ppid);
        ret = 6;
        goto Done;
    }

    p = pLine;
    while (*p)
    {
	if ('\n' == *p)
	{
	    *p = '\0';
	    break;
	}
        p++;
    }

    fprintf (fpLog, "%s %s (%u)\n", szNow, szProcess, ppid);
    printf ("password=%s\n", pLine);

Done:

    if (pLine)
    {
        memset (pLine, 0, LineLen);
        free (pLine);
        pLine = NULL;
    }

    if (fpLog)
    {
       fclose (fpLog);
       fpLog = NULL;
    }

    if (fpPwd)
    {
       fclose (fpPwd);
       fpPwd = NULL;
    }

    return ret;
}
