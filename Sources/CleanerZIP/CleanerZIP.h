#pragma once

#include <stdint.h>
#include <sys/types.h>

// Stable libarchive declarations exported by the macOS SDK. The SDK ships the
// link stub without the headers. See libarchive's archive.h and archive_entry.h.
struct archive;
struct archive_entry;

struct archive *archive_read_new(void);
int archive_read_support_format_zip_seekable(struct archive *);
int archive_read_set_format_option(struct archive *, const char *, const char *, const char *);
int archive_read_open_fd(struct archive *, int, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_free(struct archive *);

const char *archive_entry_pathname_utf8(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_xattr_count(struct archive_entry *);
const void *archive_entry_mac_metadata(struct archive_entry *, size_t *);

enum { CleanerArchiveOK = 0, CleanerArchiveEOF = 1 };
