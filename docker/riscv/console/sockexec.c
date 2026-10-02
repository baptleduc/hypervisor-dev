/*
 * sockexec PATH CMD [ARGS...]
 *
 * Bind a listening-ready Unix stream socket at PATH, hand it over as fd 0
 * and exec CMD. Stands in for systemd socket activation (wsproxy.socket) in
 * the systemd-less dom0: wsproxy expects its listening socket on stdin.
 */
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    int fd;

    if ( argc < 3 )
    {
        fprintf(stderr, "usage: %s PATH CMD [ARGS...]\n", argv[0]);
        return 2;
    }
    if ( strlen(argv[1]) >= sizeof(addr.sun_path) )
    {
        fprintf(stderr, "%s: path too long\n", argv[1]);
        return 2;
    }
    strcpy(addr.sun_path, argv[1]);

    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if ( fd < 0 )
    {
        perror("socket");
        return 1;
    }
    unlink(argv[1]);
    if ( bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 )
    {
        perror("bind");
        return 1;
    }
    if ( fd != 0 )
    {
        if ( dup2(fd, 0) < 0 )
        {
            perror("dup2");
            return 1;
        }
        close(fd);
    }
    execvp(argv[2], argv + 2);
    perror("execvp");
    return 1;
}
