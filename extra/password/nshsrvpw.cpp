/* Copyright Nash!Com - Daniel Nashed Communication Systems, 2024 */


#define VERSION "0.9.0"


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>

extern "C" {

/* ----- NOTES API HEADER FILES ---- */

#include <global.h>
#include <nsferr.h>
#include <osmisc.h>
#include <misc.h>
#include <extmgr.h>
#include <names.h>
#include <osenv.h>
#include <kfm.h>
#include <miscerr.h>
#include <bsafeerr.h>


/* Defines */

#define READ  0
#define WRITE 1


/*---- GLOBAL VARIABLES ----*/

static EMHANDLER       g_HandlerProc = NULL;
static HEMREGISTRATION g_hHandler    = NULLHANDLE;

static DWORD g_dwDebug = 0;

static char g_szCredentialProcess[MAXPATH+1] = {0};

static char g_szProgramName[]      = "NshSrvPw";
static char g_szProcess[MAXPATH+1] = {0};
static char *g_pszDisplayProcess   = g_szProcess;

/* Environment variables */

static char g_EnvCredentialProcess[] = "NshSrvPwCredentialProcess";
static char g_EnvPwSetup[]           = "NshSrvPwSetup";
static char g_EnvDebug[]             = "NshSrvPwDebug";


static void Log (const char *pszMessage)
{
    if (NULL == pszMessage)
        return;
 
    printf ("%s[%s]: %s\n", g_szProgramName, g_pszDisplayProcess, pszMessage);
    fflush (stdout);
}


static void Debug (const char *pszMessage)
{
    if (NULL == pszMessage)
        return;

    if (0 == g_dwDebug)
	return;

    printf ("%s[%s]: %s\n", g_szProgramName, g_pszDisplayProcess, pszMessage);
    fflush (stdout);
}


static void SetNonBlockFD (int fd)
{
    int flags = 0;

    flags = fcntl( fd, F_GETFL, 0);
    fcntl (fd, F_SETFL, flags | O_NONBLOCK);
}


static int pclose3 (pid_t pid)
{
    int internal_stat = 0;

    waitpid (pid, &internal_stat, 0);

    return WEXITSTATUS (internal_stat);
}


static pid_t popen3 (int *retpInputFD, int *retpOutputFD, int *retpErrorFD, int NonBlock, const char *argv[])
{
    int p_stdin[2]  = {0};
    int p_stdout[2] = {0};
    int p_stderr[2] = {0};
    pid_t pid = 0;

    if (pipe (p_stdin))
        return -1;

    if (pipe (p_stdout))
        return -1;

    if (pipe (p_stderr))
        return -1;

    if (NULL == argv[0])
        return -1;

    pid = fork();

    if (pid < 0)
    {
        /* error forking process */
        return pid;
    }
    else if (pid == 0)
    {
        /* child process */
        dup2 (p_stdin[READ], STDIN_FILENO);
        dup2 (p_stdout[WRITE], STDOUT_FILENO);
        dup2 (p_stderr[WRITE], STDERR_FILENO);

        /* close unused descriptors */
        close (p_stdin[READ]);
        close (p_stdout[READ]);
        close (p_stderr[READ]);

        close (p_stdin[WRITE]);
        close (p_stdout[WRITE]);
        close (p_stderr[WRITE]);

        /* switch child process to new binary */
        execv (argv[0], (char **) argv);

        /* this only reached when switching to the new binary did not work */
        perror ("Cannot run command");
        exit (1);
    }

    /* parent process */

    /* close unused descriptors on parent process*/
    close (p_stdin[READ]);
    close (p_stdout[WRITE]);
    close (p_stderr[WRITE]);

    /* close files or assign it to parent */

    if (retpInputFD)
    {
        *retpInputFD = p_stdin[WRITE];
    }
    else
    {
        close (p_stdin[WRITE]);
    }

    if (retpOutputFD)
    {
        *retpOutputFD = p_stdout[READ];
        if (NonBlock)
            SetNonBlockFD (*retpOutputFD);
    }
    else
    {
        close (p_stdout[READ]);
    }

    if (retpErrorFD)
    {
        *retpErrorFD = p_stderr[READ];

        if (NonBlock)
            SetNonBlockFD (*retpErrorFD);
    }
    else
    {
        close (p_stderr[READ]);
    }

    return pid;
}


static DWORD GetParam (char *pszLine, char *pszParm,  DWORD dwMaxBuffer, char *retpszBuffer, DWORD *retpdwBufferLen)
{
    char   *p     = NULL;
    char   *pParm = NULL;
    DWORD  dwLen  = 0;

    if (NULL == pszLine)
        return 0;

    if (NULL == pszParm)
        return 0;

    if (NULL == retpszBuffer)
	return 0;

    if (0 == dwMaxBuffer)
        return 0;

    if (NULL == retpdwBufferLen)
	return 0;

    /* Not a valid parameter */
    p = strstr (pszLine, "=");
    if (NULL == p)
        return 0;

    *p = '\0';
    p++;
    pParm = p;

    /* Parameter not matching */
    if (strcmp (pszLine, pszParm))
        return 0;

    /* Scan and copy buffer */
    while (*p)
    {
        if ('\n' == *p)
            break;

        if (0 == dwMaxBuffer)
        {
           Log ("Buffer too small!");
           break;
        }

        *retpszBuffer = *p;
        retpszBuffer++;
        dwLen++;
        dwMaxBuffer--;
        p++;

    } /* while Line */

    *retpdwBufferLen = dwLen;
    return 1;
}


static DWORD getp (DWORD dwMaxPwdLen, char *retpszPassword, DWORD *retpdwPasswordLen)
{
    pid_t   pid      =  0;
    DWORD   dwPwdLen =  0;
    DWORD   dwFound  =  0;
    int     ret      =  0;
    int     InputFD  = -1;
    int     OutputFD = -1;
    int     ErrorFD  = -1;

    char    *pLine   = NULL;
    size_t  LineLen  = 4096;
    ssize_t nread    = 0;

    const char *args[] = { g_szCredentialProcess, NULL };

    FILE *fpRead  = NULL;
    FILE *fpWrite = NULL;

    if (NULL == retpszPassword)
        return 0;

    if (NULL == retpdwPasswordLen)
	return 0;

    /* In any case init buffer and return len */
    *retpszPassword    = '\0';
    *retpdwPasswordLen = 0;

    pid = popen3 (&InputFD, &OutputFD, &ErrorFD, 0, args);

    if (pid < 1)
    {
	Log ("Cannot open process");
        perror ("Cannot open process");
        goto Done;
    }

    fpRead = fdopen (OutputFD, "r");
    if (NULL == fpRead)
    {
	Log ("Cannot open process read file descriptor");
        goto Done;
    }

    fpWrite = fdopen (InputFD, "w");
    if (NULL == fpWrite)
    {
	Log ("Cannot open process write file descriptor");
        goto Done;
    }

    pLine = (char *) malloc (LineLen);

    if (NULL == pLine)
    {
        Log ("Cannot allocate read buffer");
        goto Done;
    }

    while ( -1 != (nread = getline (&pLine, &LineLen, fpRead)))
    {
        dwFound += GetParam (pLine, "password", dwMaxPwdLen, retpszPassword, retpdwPasswordLen);
    }

    if (g_dwDebug)
    {
	if (retpdwPasswordLen)
        {	
            printf ("%s[%s]: Password returned: %u\n", g_szProgramName, g_pszDisplayProcess, *retpdwPasswordLen);
            fflush (stdout);
	}
    }

Done:

    if (pLine)
    {
	memset (pLine, 0, LineLen);
        free (pLine);
        pLine = NULL;
    }

   if (fpRead)
    {
        fclose (fpRead);
        fpRead = NULL;
    }

    if (fpWrite)
    {
        fclose (fpWrite);
        fpWrite = NULL;
    }

    if (-1 != InputFD)
    {
        ret = close (InputFD);
        InputFD = -1;
    }

    if (-1 != OutputFD)
    {
        ret = close (OutputFD);
        OutputFD = -1;
    }

    if (-1 != ErrorFD)
    {
        ret = close (ErrorFD);
        ErrorFD = -1;
    }

    if (pid > 0)
    {
        ret = pclose3 (pid);
        pid = 0;
    }

    return dwFound;
}


STATUS LNCALLBACK NshSrvPwExtHandler (EMRECORD far *pRecord)
{
    STATUS error         = NOERROR;
    DWORD  dwMaxPwdLen   = 0;
    DWORD  dwDataLen     = 0;
    DWORD  *pdwLength    = NULL;
    char   *pszPassword  = NULL;
    char   *pszFileName  = NULL;
    char   *pszOwnerName = NULL;
    BYTE   *pData        = NULL;
    VARARG_PTR pArgs;

    if (NULL == pRecord)
    {
	Log ("No EM Record");
        return ERR_EM_CONTINUE;
    }

    if (pRecord->EId != EM_GETPASSWORD)
    {
	Log ("Wrong EM Record");
        return ERR_EM_CONTINUE;
    }

    if (NOERROR != pRecord->Status)
    {
	Log ("Invalid status");
        return ERR_EM_CONTINUE;
    }

    /* Fetch the arguments */
    VARARG_COPY(pArgs, pRecord->Ap);

    dwMaxPwdLen   = va_arg (pArgs, DWORD);
    pdwLength     = va_arg (pArgs, DWORD *);
    pszPassword   = va_arg (pArgs, char *);
    pszFileName   = va_arg (pArgs, char *);
    pszOwnerName  = va_arg (pArgs, char *);
    dwDataLen     = va_arg (pArgs, DWORD);
    pData         = va_arg (pArgs, BYTE *);

    if (0 == dwMaxPwdLen)
    {
        Log ("Password buffer is 0");
        return ERR_EM_CONTINUE;
    }

    if (NULL == pdwLength)
    {
        Log ("Password buffer pointer is NULL");
        return ERR_EM_CONTINUE;
    }

    if (NULL == pszPassword)
    {
	Log ("Password buffer is NULL");
        return ERR_EM_CONTINUE;
    }

    getp (dwMaxPwdLen, pszPassword, pdwLength);

    if (*pdwLength)
    {
        return ERR_BSAFE_EXTERNAL_PASSWORD;
    }

Done:

    return ERR_EM_CONTINUE;
}


STATUS LNPUBLIC SetPassword (char *pszCurrentPassword, char *pszNewPassword)
{
    STATUS error = NOERROR;
    char   szKeyFileName[MAXPATH+1] = {0};

    if (0 == OSGetEnvironmentLong (g_EnvPwSetup))
        return NOERROR;

    if (FALSE == OSGetEnvironmentString ("ServerKeyFileName", szKeyFileName, sizeof (szKeyFileName)))
    {
        if (FALSE == OSGetEnvironmentString ("KeyFileName", szKeyFileName, sizeof (szKeyFileName)))
            *szKeyFileName = '\0';
    }

    if ('\0' == *szKeyFileName)
    {
	Log ("Cannot set password - No KeyFileName set");
        goto Done;
    }

    error = SECKFMChangePassword (szKeyFileName, pszCurrentPassword, pszNewPassword);

    if (error)
    {
        printf("%s: Cannot set password -- Error code: 0x%x\n", g_szProgramName, error);
    }
    else
    {
        Log ("Password successfully set");
        OSSetEnvironmentInt (g_EnvPwSetup, 0);
    }

Done:

    return error;
}


STATUS LNPUBLIC MainEntryPoint()
{
    STATUS  error = NOERROR;
    DWORD   dwPasswordLen = 0;
    char    *p = g_szProcess;
    char    szPassword[65] = {0};
    ssize_t len = 0;

    g_dwDebug = OSGetEnvironmentLong (g_EnvDebug);

    len = readlink ("/proc/self/exe", g_szProcess, sizeof (g_szProcess));

    if (0 == len)
    {
	printf ("%s: Cannot get process name\n", g_szProgramName);
	error = ERR_MISC_INVALID_ARGS;
        goto Done;
    }

    /* Get display process name */
    while (*p)
    {
        if ('/' == *p)
            g_pszDisplayProcess = p+1;
        p++;
    }

    if (FALSE == OSGetEnvironmentString (g_EnvCredentialProcess, g_szCredentialProcess, sizeof (g_szCredentialProcess)))
    {
        *g_szCredentialProcess = '\0';
    }

    if ('\0' == *g_szCredentialProcess)
    {
        Log ("No Credential Process configured");
	error = ERR_MISC_INVALID_ARGS;
	goto Done;
    }

    if (OSGetEnvironmentLong (g_EnvPwSetup))
    {
        getp (sizeof (szPassword)-1, szPassword, &dwPasswordLen);
        szPassword[dwPasswordLen] = '\0';
        SetPassword (NULL, szPassword);
    }

    error = EMRegister (EM_GETPASSWORD, EM_REG_BEFORE, NshSrvPwExtHandler, 0, &g_hHandler);

    if (error)
    {
        printf ("%s[%s]: Error initializing EM routine. Error Code = %d", g_szProgramName, g_pszDisplayProcess, error);
        fflush (stdout);
        goto Done;
    }

    if (g_dwDebug)
    {
        printf ("%s[%s]: Initialized\n", g_szProgramName, g_pszDisplayProcess);
        fflush (stdout);
    }

Done:

    return error;
}


/* extern */
}

