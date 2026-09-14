// Read-only Android-shell stdin audit. It never opens a VM or writes outside
// its own stdout: it reports the descriptor type plus poll/epoll acceptance.
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *kind(mode_t mode) {
  if (S_ISREG(mode)) return "regular";
  if (S_ISFIFO(mode)) return "fifo_or_pipe";
  if (S_ISSOCK(mode)) return "socket";
  if (S_ISCHR(mode)) return "character";
  if (S_ISBLK(mode)) return "block";
  if (S_ISDIR(mode)) return "directory";
  return "other";
}

static int audit_fd(const char *label, int fd) {
  struct stat st;
  struct pollfd pfd = { .fd = fd, .events = POLLIN, .revents = 0 };
  struct epoll_event ev = { .events = EPOLLIN, .data.fd = fd };
  char target[256] = {0};
  int epfd, rc, saved;
  ssize_t n;

  char proc_path[64];
  snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
  n = readlink(proc_path, target, sizeof(target) - 1);
  if (n >= 0) target[n] = '\0';
  if (fstat(fd, &st) != 0) {
    printf("%s_FSTAT_ERRNO=%d\n", label, errno);
    return 1;
  }
  printf("%s_LINK=%s\n", label, n >= 0 ? target : "<readlink-failed>");
  printf("%s_TYPE=%s\n", label, kind(st.st_mode));
  printf("%s_MODE=%#o\n", label, st.st_mode);
  printf("%s_ISATTY=%d\n", label, isatty(fd));

  errno = 0;
  rc = poll(&pfd, 1, 0);
  saved = errno;
  printf("%s_POLL_RC=%d ERRNO=%d REVENTS=%#x\n", label, rc, saved, (unsigned)pfd.revents);

  epfd = epoll_create1(EPOLL_CLOEXEC);
  if (epfd < 0) {
    printf("EPOLL_CREATE_ERRNO=%d\n", errno);
    return 1;
  }
  errno = 0;
  rc = epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
  saved = errno;
  printf("%s_EPOLL_CTL_ADD_RC=%d ERRNO=%d\n", label, rc, saved);
  close(epfd);
  return 0;
}

int main(void) {
  int reopened;
  int result = audit_fd("FD0", STDIN_FILENO);
  // Mirrors AVF vm run when supplied --console-in /proc/self/fd/0.
  reopened = open("/proc/self/fd/0", O_RDONLY | O_CLOEXEC);
  if (reopened < 0) {
    printf("REOPEN_ERRNO=%d\n", errno);
    return 1;
  }
  result |= audit_fd("REOPEN", reopened);
  close(reopened);
  return result;
}
