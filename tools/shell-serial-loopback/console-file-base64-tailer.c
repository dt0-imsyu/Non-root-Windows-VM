/* Emit appended --console bytes as O:<base64> records for the ADB text link. */
#include <fcntl.h>
#include <stdint.h>
#include <sys/stat.h>
#include <unistd.h>

static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int write_all(int fd, const void *p, unsigned long n) {
  const char *s = (const char *)p;
  while (n) { long r = write(fd, s, n); if (r <= 0) return -1; s += r; n -= (unsigned long)r; }
  return 0;
}

static int emit_record(const uint8_t *in, unsigned long n) {
  char out[2 + ((768 + 2) / 3) * 4 + 1];
  unsigned long i = 0, o = 0;
  out[o++] = 'O'; out[o++] = ':';
  while (i + 2 < n) {
    out[o++] = b64[in[i] >> 2];
    out[o++] = b64[((in[i] & 3) << 4) | (in[i + 1] >> 4)];
    out[o++] = b64[((in[i + 1] & 15) << 2) | (in[i + 2] >> 6)];
    out[o++] = b64[in[i + 2] & 63];
    i += 3;
  }
  if (i < n) {
    out[o++] = b64[in[i] >> 2];
    if (i + 1 < n) {
      out[o++] = b64[((in[i] & 3) << 4) | (in[i + 1] >> 4)];
      out[o++] = b64[(in[i + 1] & 15) << 2]; out[o++] = '=';
    } else { out[o++] = b64[(in[i] & 3) << 4]; out[o++] = '='; out[o++] = '='; }
  }
  out[o++] = '\n';
  return write_all(1, out, o);
}

int main(int argc, char **argv) {
  uint8_t buf[768]; long off = 0;
  if (argc != 2) return 64;
  for (;;) {
    struct stat st; int fd = open(argv[1], O_RDONLY);
    if (fd < 0) { usleep(20000); continue; }
    if (fstat(fd, &st) == 0 && st.st_size > off && lseek(fd, off, SEEK_SET) >= 0) {
      long left = st.st_size - off;
      while (left > 0) {
        unsigned long ask = left > (long)sizeof(buf) ? sizeof(buf) : (unsigned long)left;
        long got = read(fd, buf, ask);
        if (got <= 0 || emit_record(buf, (unsigned long)got) != 0) { close(fd); return 1; }
        off += got; left -= got;
      }
    }
    close(fd); usleep(20000);
  }
}
