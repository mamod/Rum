package Rum::Loop::Core::Win32;

package #override core module
        Rum::Loop::Core;
use Rum::Loop::Flags qw(:IO);
use IO::Socket;
use warnings;
use strict;

use base qw/Exporter/;
our @EXPORT = qw (
    cloexec
    nonblock
    CreateIoCompletionPort
    SetHandleInformation
    FdGetOsFHandle
    GetOsFHandle
    duplicate_handle
    duplicate_file
    GetStdHandle
);

use strict;
use warnings;
use IO::Handle;
use Socket;
use Win32::API;
use Win32;
use Win32API::File qw(GetOsFHandle FdGetOsFHandle OsFHandleOpen OsFHandleOpenFd CloseHandle);
use Data::Dumper;

###constants
my $INVALID_HANDLE_VALUE  = -1;
my $HANDLE_FLAG_INHERIT   = 0x00000001;
my $DUPLICATE_SAME_ACCESS = 0x00000002;
my $STD_INPUT_HANDLE = -10;
my $STD_OUTPUT_HANDLE = -11;
my $STD_ERROR_HANDLE = -12;

##Fuunctions
Win32::API->Import('KERNEL32', 'HFILE CreateIoCompletionPort(HANDLE FH,HANDLE EPort,ULONG CKey, DWORD NThreads)');
Win32::API->Import('KERNEL32', 'BOOL SetHandleInformation(HANDLE hObject,DWORD dwMask,DWORD dwFlags)');
Win32::API->Import('KERNEL32', 'DWORD WaitForMultipleObjects(DWORD nCount,HANDLE *lpHandles,BOOL bWaitAll,DWORD dwMilliseconds)');
Win32::API->Import('KERNEL32', 'DWORD WaitForSingleObject(HANDLE hHandle,DWORD dwMilliseconds)');
Win32::API->Import('KERNEL32', 'DWORD GetExitCodeProcess(HANDLE hProcess,LPDWORD lpExitCode)');
Win32::API->Import('KERNEL32', 'BOOL FreeConsole()');
Win32::API->Import('KERNEL32', 'HANDLE GetCurrentProcess()');

Win32::API->Import(
    'kernel32',
    'GetStdHandle',
    'N',
    'I'
);

Win32::API->Import(
    'kernel32',
    'OpenProcess',
    'NNN',
    'N',
);

Win32::API->Import(
    'kernel32',
    'DuplicateHandle',
    'NNNPNNN',
    'N',
);

Win32::API->Import(
    'Ws2_32.dll',
    'WSADuplicateSocketW',
    'NNP',
    'N',
);

Win32::API->Import(
    'kernel32',
    'CreateProcess',
    'PPNNNNPNPP',
    'I'
);


Win32::API->Import(
    'Ws2_32.dll',
    'WSASocket',
    'NNNPNN',
    'I'
);

##error report
sub _lastError {
    return Win32::FormatMessage(Win32::GetLastError());
}

sub loop_init {
    my $loop = shift;
    
    $loop->{iocp} = CreateIoCompletionPort($INVALID_HANDLE_VALUE, NULL, 0, 1);
    if ($loop->{iocp} == NULL) {
        die _lastError();
    }
}

sub make_inheritable {
    my $fd = shift;
    $fd = defined (fileno $fd) ? fileno $fd : $fd;
    my $fdHandle = FdGetOsFHandle($fd);
    
    if (!SetHandleInformation($fdHandle, $HANDLE_FLAG_INHERIT | 0x00000002, 1)) {
        die _lastError();
    }
    
    return $fdHandle;
}

sub cloexec {
    my $fd = shift;
    my $set = shift;
    my $flag = $set ? 0 : 1;
    $fd = defined (fileno $fd) ? fileno $fd : $fd;
    my $fdHandle = FdGetOsFHandle($fd);
    
    if (!SetHandleInformation($fdHandle, $HANDLE_FLAG_INHERIT, $flag)) {
        return;
    }
    
    return 1;
}

sub nonblock {
    my $fd = shift;
    my $set = shift;
    ioctl($fd, 0x8004667e, pack("L!",$set ? 1 : 0))
            or return;
    
    return 1;
}

sub duplicate_handle {
    my $handle = shift;
    
    my $dupHandle = "\0\0\0\0";
    if (!DuplicateHandle(-1, $handle, -1, $dupHandle,
                         0, 1, $DUPLICATE_SAME_ACCESS )){
        $! = $^E+0;
        return;
    }
    
    $dupHandle = unpack "V", $dupHandle;
    return $dupHandle;
}

sub duplicate_file {
    my $fd = shift;
    $fd = defined (fileno $fd) ? fileno $fd : $fd;
    my $fhandle = FdGetOsFHandle( $fd ) or return;
    return duplicate_handle($fhandle);
}

sub process_status {
    my $handle = shift;
    my $status = "\0\0\0\0";
    GetExitCodeProcess($handle,$status);
    $status = unpack "V", $status;
    return $status;
}


sub disable_stdio_inheritance {
    my $handle;
    
    #Make the windows stdio handles non-inheritable.
    $handle = GetStdHandle($STD_INPUT_HANDLE);
    if ($handle && $handle != $INVALID_HANDLE_VALUE) {
        SetHandleInformation($handle, $HANDLE_FLAG_INHERIT, 0);
    }
    
    $handle = GetStdHandle($STD_OUTPUT_HANDLE);
    if ($handle && $handle != $INVALID_HANDLE_VALUE) {
        SetHandleInformation($handle, $HANDLE_FLAG_INHERIT, 0);
    }
    
    $handle = GetStdHandle($STD_ERROR_HANDLE);
    if ($handle && $handle != $INVALID_HANDLE_VALUE) {
        SetHandleInformation($handle, $HANDLE_FLAG_INHERIT, 0);
    }
    
    #for (0..5){
    #    cloexec($_, 1);
    #}
    
    #Make inherited CRT FDs non-inheritable.
    #GetStartupInfoW(&si);
    #if (uv__stdio_verify(si.lpReserved2, si.cbReserved2))
    #    uv__stdio_noinherit(si.lpReserved2);
}

1;
