#include <cstdlib>
#include <cstring>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <algorithm>
#include <vector>
#include <string>
#include <utility>
#import <CoreFoundation/CoreFoundation.h>
#include <marisa.h>

// CFBurstTrie private API — present in macOS CoreFoundation, used by iOS ≤16 format
typedef void *CFBurstTrieRef;
typedef void *CFBurstTrieCursorRef;
// Callback: (context, key_bytes, key_len, payload_u32, flags)
typedef void (*CFBurstTrieTraversalCallback)(void *, const uint8_t *, unsigned int, unsigned int, uint8_t *);
extern "C" {
    // Read APIs
    CFBurstTrieRef     CFBurstTrieCreateFromMapBytes(char *buffer, unsigned long length);
    CFBurstTrieCursorRef CFBurstTrieCreateCursorForBytes(CFBurstTrieRef, const uint8_t *, unsigned long);
    void               CFBurstTrieSetCursorForBytes(CFBurstTrieRef, CFBurstTrieCursorRef, const uint8_t *, unsigned long);
    void               CFBurstTrieTraverseFromCursor(CFBurstTrieCursorRef, void *, CFBurstTrieTraversalCallback);
    void               CFBurstTrieRelease(CFBurstTrieRef);
    void               CFBurstTrieCursorRelease(CFBurstTrieCursorRef);
    // Write APIs (for Marisa→iOS16 conversion)
    CFBurstTrieRef     CFBurstTrieCreate(void);
    void               CFBurstTrieAddUTF8String(CFBurstTrieRef, uint8_t *, long, long);
    unsigned char      CFBurstTrieSerializeWithFileDescriptor(CFBurstTrieRef, int);
}

struct CFBurstEntry { std::string key; uint32_t payload; };

static void burst_trie_callback(void *ctx, const uint8_t *key, unsigned int keyLen,
                                 unsigned int payload, uint8_t *) {
    reinterpret_cast<std::vector<CFBurstEntry>*>(ctx)->push_back(
        { std::string(reinterpret_cast<const char*>(key), keyLen), payload });
}

// Emoji keyword search index format (FindReplace.dat / CharacterPicker.dat)
static constexpr uint32_t FINDREPLACE_MAGIC = 0x3FA8BDD1;

// Convert iOS 17+ Marisa trie format → iOS 16 CFBurstTrie format.
// Writes a new file at the path pointed to by `fo`.
static int convert_findreplace_v16(FILE *fp, FILE *fo) {
    struct {
        uint32_t magic;
        uint16_t version;
        uint16_t flags;
        uint32_t trie_blob_size;
        uint32_t index_array_count;
    } hdr;

    if (fread(&hdr, sizeof(hdr), 1, fp) != 1 ||
        hdr.magic != FINDREPLACE_MAGIC || hdr.version != 1) {
        fprintf(stderr, "Error: Invalid header for FindReplace conversion\n");
        return EXIT_FAILURE;
    }
    if (hdr.trie_blob_size < 4) {
        fprintf(stderr, "Error: Trie blob too small\n");
        return EXIT_FAILURE;
    }

    uint8_t *trie_blob = (uint8_t *)malloc(hdr.trie_blob_size);
    if (!trie_blob || fread(trie_blob, 1, hdr.trie_blob_size, fp) != hdr.trie_blob_size) {
        free(trie_blob);
        fprintf(stderr, "Error: Failed to read trie blob\n");
        return EXIT_FAILURE;
    }

    uint32_t first4 = *(uint32_t *)trie_blob;
    if (first4 + 4 > hdr.trie_blob_size) {
        // Already CFBurstTrie (iOS ≤16) — copy the file as-is
        free(trie_blob);
        fprintf(stderr, "Note: Source is already CFBurstTrie (iOS ≤16), copying verbatim\n");
        fseek(fp, 0, SEEK_SET);
        uint8_t copy_buf[65536];
        size_t n;
        while ((n = fread(copy_buf, 1, sizeof(copy_buf), fp)) > 0)
            fwrite(copy_buf, 1, n, fo);
        return EXIT_SUCCESS;
    }

    // Marisa trie: trie_blob = [uint32 inner_marisa_size][marisa_data][payload_table]
    bool null_term = (hdr.flags & 1) != 0;
    uint32_t inner_marisa_size = first4;
    if ((uint64_t)inner_marisa_size + 4 + 4 > hdr.trie_blob_size) {
        free(trie_blob);
        fprintf(stderr, "Error: Marisa inner size exceeds blob\n");
        return EXIT_FAILURE;
    }
    uint32_t payload_count = (hdr.trie_blob_size - inner_marisa_size - 4) / 4;
    const uint32_t *payload_table = (const uint32_t *)(trie_blob + 4 + inner_marisa_size);

    uint16_t *index_array = nullptr;
    if (hdr.index_array_count > 0) {
        index_array = (uint16_t *)malloc(hdr.index_array_count * sizeof(uint16_t));
        if (!index_array ||
            fread(index_array, sizeof(uint16_t), hdr.index_array_count, fp) != hdr.index_array_count) {
            free(trie_blob);
            free(index_array);
            fprintf(stderr, "Error: Failed to read index array\n");
            return EXIT_FAILURE;
        }
    }

    // Load Marisa trie from memory
    marisa::Trie marisa_trie;
    try {
        marisa_trie.map(trie_blob + 4, inner_marisa_size);
    } catch (const marisa::Exception &e) {
        free(trie_blob);
        free(index_array);
        fprintf(stderr, "Error: Marisa map failed: %s\n", e.what());
        return EXIT_FAILURE;
    }

    if (marisa_trie.num_keys() != payload_count) {
        fprintf(stderr, "Warning: Marisa key count (%zu) != payload count (%u)\n",
                marisa_trie.num_keys(), payload_count);
    }

    // Enumerate all keys and collect their emoji indices
    struct KV { std::string key; std::vector<uint16_t> indices; };
    std::vector<KV> entries;
    entries.reserve(payload_count);

    marisa::Agent agent;
    agent.set_query("");
    while (marisa_trie.predictive_search(agent)) {
        size_t key_id = agent.key().id();
        uint32_t p = (key_id < payload_count) ? payload_table[key_id] : 0;
        uint32_t start = p & 0x3FFFFF;
        uint32_t count = (p >> 22) & 0x3FF;

        std::vector<uint16_t> indices;
        if (!null_term) {
            for (uint32_t i = 0; i < count; ++i)
                if (start + i < hdr.index_array_count)
                    indices.push_back(index_array[start + i]);
        } else {
            for (uint32_t i = start; i < hdr.index_array_count && index_array[i]; ++i)
                indices.push_back(index_array[i]);
        }
        entries.push_back({ std::string(agent.key().ptr(), agent.key().length()),
                            std::move(indices) });
    }

    free(trie_blob);
    free(index_array);

    // Build new compact (count-based) index array and payload map
    std::vector<uint16_t> new_index;
    new_index.reserve(hdr.index_array_count);

    CFBurstTrieRef bt = CFBurstTrieCreate();
    for (auto &e : entries) {
        uint32_t new_start = (uint32_t)new_index.size();
        uint32_t new_count = std::min((uint32_t)e.indices.size(), (uint32_t)0x3FF);
        for (uint32_t i = 0; i < new_count; ++i)
            new_index.push_back(e.indices[i]);
        uint32_t packed = new_start | (new_count << 22);
        CFBurstTrieAddUTF8String(bt, (uint8_t *)e.key.data(), (long)e.key.size(), (long)packed);
    }

    // Serialize CFBurstTrie directly to the output file, then fix up the header.
    // Write a placeholder header first so the blob follows immediately.
    long hdr_offset = (long)lseek(fileno(fo), 0, SEEK_CUR);
    fwrite(&hdr, sizeof(hdr), 1, fo);
    fflush(fo);  // flush C buffer before raw fd write

    long pos_before = (long)lseek(fileno(fo), 0, SEEK_CUR);
    unsigned char ok = CFBurstTrieSerializeWithFileDescriptor(bt, fileno(fo));
    CFBurstTrieRelease(bt);

    if (!ok) {
        fprintf(stderr, "Error: CFBurstTrieSerializeWithFileDescriptor failed\n");
        return EXIT_FAILURE;
    }

    long pos_after = (long)lseek(fileno(fo), 0, SEEK_CUR);
    long blob_len = pos_after - pos_before;

    // Resync C FILE* position after raw fd writes, then append index array
    fseek(fo, pos_after, SEEK_SET);
    fwrite(new_index.data(), sizeof(uint16_t), new_index.size(), fo);

    // Seek back and overwrite placeholder header with correct sizes
    hdr.flags = 0x0000;
    hdr.trie_blob_size = (uint32_t)blob_len;
    hdr.index_array_count = (uint32_t)new_index.size();
    fseek(fo, hdr_offset, SEEK_SET);
    fwrite(&hdr, sizeof(hdr), 1, fo);

    fprintf(stderr, "Converted: %zu keywords -> iOS 16 CFBurstTrie (%ld B blob, %u indices)\n",
            entries.size(), blob_len, (uint32_t)new_index.size());
    return EXIT_SUCCESS;
}

static int read_findreplace(FILE *fp) {
    struct {
        uint32_t magic;
        uint16_t version;
        uint16_t flags;
        uint32_t trie_blob_size;
        uint32_t index_array_count;
    } hdr;
    if (fread(&hdr, sizeof(hdr), 1, fp) != 1) {
        fprintf(stderr, "Error: Failed to read header\n");
        return EXIT_FAILURE;
    }
    if (hdr.magic != FINDREPLACE_MAGIC) {
        fprintf(stderr, "Error: Invalid magic 0x%08X (expected 0x%08X)\n", hdr.magic, FINDREPLACE_MAGIC);
        return EXIT_FAILURE;
    }
    if (hdr.version != 1) {
        fprintf(stderr, "Error: Unsupported version %u\n", hdr.version);
        return EXIT_FAILURE;
    }
    bool null_term = (hdr.flags & 1) != 0;

    if (hdr.trie_blob_size < 4) {
        fprintf(stderr, "Error: Trie blob too small\n");
        return EXIT_FAILURE;
    }

    uint8_t *trie_blob = (uint8_t *)malloc(hdr.trie_blob_size);
    if (!trie_blob) {
        fprintf(stderr, "Error: Out of memory\n");
        return EXIT_FAILURE;
    }
    if (fread(trie_blob, 1, hdr.trie_blob_size, fp) != hdr.trie_blob_size) {
        free(trie_blob);
        fprintf(stderr, "Error: Failed to read trie blob\n");
        return EXIT_FAILURE;
    }

    // Detect trie engine: if the first uint32 would overflow as a Marisa inner-size,
    // the blob is a serialized CFBurstTrie (used by iOS ≤16).
    uint32_t first4 = *(uint32_t *)trie_blob;
    bool is_cft = (first4 + 4 > hdr.trie_blob_size);

    printf("Format:             Emoji Keyword Search Index\n");
    printf("Trie engine:        %s\n", is_cft ? "CFBurstTrie (iOS ≤16)" : "Marisa LOUDS (iOS 17+)");
    printf("Version:            %u\n", hdr.version);
    printf("Flags:              0x%04X%s\n", hdr.flags, null_term ? " [null-terminated]" : "");
    printf("Trie blob size:     0x%X (%u bytes)\n", hdr.trie_blob_size, hdr.trie_blob_size);
    printf("Index array count:  %u entries\n", hdr.index_array_count);

    // --- Marisa-specific stats ---
    uint32_t inner_marisa_size = 0;
    uint32_t payload_count = 0;
    const uint32_t *payload_table = nullptr;
    if (!is_cft) {
        inner_marisa_size = first4;
        payload_count = (hdr.trie_blob_size - inner_marisa_size - 4) / 4;
        payload_table = (const uint32_t *)(trie_blob + 4 + inner_marisa_size);
        printf("Marisa trie size:   0x%X (%u bytes)\n", inner_marisa_size, inner_marisa_size);
        printf("Keyword count:      %u\n", payload_count);
        const uint8_t *marisa_data = trie_blob + 4;
        bool ok = inner_marisa_size >= 15 &&
                  *(uint64_t *)marisa_data == 0x2065766F6C206557ULL;
        printf("Marisa signature:   %s\n", ok ? "OK" : "MISSING");
    }

    // --- Read index array ---
    uint16_t *index_array = nullptr;
    if (hdr.index_array_count > 0) {
        index_array = (uint16_t *)malloc(hdr.index_array_count * sizeof(uint16_t));
        if (!index_array) {
            free(trie_blob);
            fprintf(stderr, "Error: Out of memory\n");
            return EXIT_FAILURE;
        }
        if (fread(index_array, sizeof(uint16_t), hdr.index_array_count, fp) != hdr.index_array_count) {
            free(trie_blob);
            free(index_array);
            fprintf(stderr, "Error: Failed to read index array\n");
            return EXIT_FAILURE;
        }
    }

    // Helper to print the emoji indices for a given packed payload ref
    auto print_indices = [&](uint32_t p) {
        uint32_t start = p & 0x3FFFFF;
        uint32_t count = (p >> 22) & 0x3FF;
        printf("[");
        if (!null_term) {
            for (uint32_t j = 0; j < count; j++) {
                if (start + j >= hdr.index_array_count) break;
                if (j > 0) printf(", ");
                printf("0x%X", index_array[start + j]);
            }
        } else {
            uint32_t j = start;
            bool first = true;
            while (j < hdr.index_array_count && index_array[j]) {
                if (!first) printf(", ");
                printf("0x%X", index_array[j]);
                first = false;
                ++j;
            }
        }
        printf("]");
    };

    if (is_cft) {
        // --- CFBurstTrie path: enumerate using CoreFoundation API ---
        CFBurstTrieRef trie = CFBurstTrieCreateFromMapBytes((char *)trie_blob, hdr.trie_blob_size);
        if (!trie) {
            free(trie_blob);
            free(index_array);
            fprintf(stderr, "Error: CFBurstTrieCreateFromMapBytes failed — blob may be corrupt\n");
            return EXIT_FAILURE;
        }
        CFBurstTrieCursorRef cursor = CFBurstTrieCreateCursorForBytes(trie, nullptr, 0);
        if (!cursor) {
            CFBurstTrieRelease(trie);
            free(trie_blob);
            free(index_array);
            fprintf(stderr, "Error: CFBurstTrieCreateCursorForBytes failed\n");
            return EXIT_FAILURE;
        }
        // Position cursor at root (empty prefix) to enumerate all keys
        CFBurstTrieSetCursorForBytes(trie, cursor, nullptr, 0);

        std::vector<CFBurstEntry> entries;
        CFBurstTrieTraverseFromCursor(cursor, &entries, burst_trie_callback);
        CFBurstTrieCursorRelease(cursor);
        CFBurstTrieRelease(trie);

        printf("Keyword count:      %zu\n", entries.size());

        std::sort(entries.begin(), entries.end(),
                  [](const CFBurstEntry &a, const CFBurstEntry &b){ return a.key < b.key; });

        printf("\n--- Keyword -> Emoji Index Table (%zu entries) ---\n", entries.size());
        for (const auto &e : entries) {
            uint32_t start = e.payload & 0x3FFFFF;
            uint32_t count = (e.payload >> 22) & 0x3FF;
            printf("%-30s start=0x%-5X count=%-3u -> ", e.key.c_str(), start, count);
            print_indices(e.payload);
            printf("\n");
        }
    } else {
        // --- Marisa path: dump raw payload table (keys embedded in trie, not shown) ---
        printf("\n--- Keyword Payload Table (%u entries) ---\n", payload_count);
        for (uint32_t i = 0; i < payload_count; i++) {
            uint32_t p = payload_table[i];
            uint32_t start = p & 0x3FFFFF;
            uint32_t count = (p >> 22) & 0x3FF;
            printf("[%5u] start=0x%-5X count=%-3u -> ", i, start, count);
            print_indices(p);
            printf("\n");
        }
    }

    free(trie_blob);
    free(index_array);
    return EXIT_SUCCESS;
}

// Metadata flags
static constexpr uint32_t FLAG_SKIN           = 0x40;
static constexpr uint32_t FLAG_COMMON         = 0x80;
static constexpr uint32_t FLAG_HAIR           = 0x100;
static constexpr uint32_t FLAG_FEMALE_LEGACY  = 0x200;
static constexpr uint32_t FLAG_MALE_LEGACY    = 0x100;
static constexpr uint32_t FLAG_FEMALE_MODERN  = 0x20000;
static constexpr uint32_t FLAG_MALE_MODERN    = 0x10000;
static constexpr uint32_t FLAG_STYLE_1        = 0x20;
static constexpr uint32_t FLAG_STYLE_2        = 0x10;

// iOS version limits
static constexpr int MAX_EMOJI_IOS_10_1_1     = 3206;

bool modern = false;

bool has_skin(uint32_t d0) {
    return d0 & FLAG_SKIN;
}

bool is_common(uint32_t d0) {
    return d0 & FLAG_COMMON;
}

int skin_tone(uint32_t d0) {
    return modern ? ((d0 >> 20) & 0xF) : d0 >> 12;
}

bool has_hair(uint32_t d0) {
    return d0 & FLAG_HAIR;
}

int hair_style(uint32_t d0) {
    return d0 >> 24;
}

int presentation_style(uint32_t d0) {
    if (d0 & FLAG_STYLE_1)
        return 1;
    if (d0 & FLAG_STYLE_2)
        return 2;
    return 0;
}

char gender(uint32_t d0) {
    if (modern) {
        if (d0 & FLAG_FEMALE_MODERN)
            return 'F';
        if (d0 & FLAG_MALE_MODERN)
            return 'M';
    } else {
        if (d0 & FLAG_FEMALE_LEGACY)
            return 'F';
        if (d0 & FLAG_MALE_LEGACY)
            return 'M';
    }
    return '-';
}

void read_str(FILE *fp, char *str, size_t maxlen) {
    int b;
    size_t n = 0;
    while (n < maxlen - 1 && (b = fgetc(fp)) != EOF && b != '\0')
        str[n++] = (unsigned char)b;
    str[n] = '\0';
}

bool is_valid_mode(int m) {
    return m == 0 || m == 1 || m == 2 || m == 3 || m == 16;
}

void usage() {
    printf("Usage: emdreader -i <path-to-metadata-dat>\n");
    printf("Usage: emdreader -i <input-dat> -e <export-mode> -o <output-dat>\n");
    printf("  emojimeta modes: 3 = iOS 17.0+, 2 = iOS 12.1-16.7, 1 = pre-iOS 12.1, 0 = iOS 10.1.1\n");
    printf("  trie modes:     16 = iOS \u226416 CFBurstTrie (converts from Marisa)\n");
}

int main(int argc, char *argv[], char *envp[]) {
    int opt;
    int intype = -1;
    int outtype = -1;
    int filter = 0xffffff;
    FILE *fp = NULL;
    FILE *fo = NULL;
    bool out = false;
    while ((opt = getopt(argc, argv, "i:o:e:f:h")) != -1) {
        switch (opt) {
            case 'e':
                outtype = atoi(optarg);
                break;
            case 'i': {
                if ((fp = fopen(optarg, "rb")) == NULL) {
                    fprintf(stderr, "Error: Unable to open input file '%s' for reading\n", optarg);
                    return EXIT_FAILURE;
                }
                break;
            }
            case 'o': {
                fo = fopen(optarg, "wb+");
                if (fo == NULL) {
                    fprintf(stderr, "Error: Unable to open output file '%s' for writing\n", optarg);
                    if (fp) fclose(fp);
                    return EXIT_FAILURE;
                }
                break;
            }
            case 'f': {
                filter = strtoul(optarg, NULL, 16);
                break;
            }
            case 'h':
                usage();
                return EXIT_SUCCESS;
        }
    }

    if (fp == NULL) {
        fprintf(stderr, "Error: Input file required. Use -i <path>\n");
        usage();
        return EXIT_FAILURE;
    }

    if (is_valid_mode(outtype)) {
        if (fo == NULL) {
            fprintf(stderr, "Error: Output file required when using -e. Use -o <path>\n");
            fclose(fp);
            return EXIT_FAILURE;
        }
        out = true;
    }

    uint16_t buf[1];
    uint16_t paddings[] = { 10, 14, 16, 16 };

    uint32_t count32;
    fread(&count32, 4, 1, fp);

    // Auto-detect FindReplace / trie-index format
    if (count32 == FINDREPLACE_MAGIC) {
        if (out && outtype == 16) {
            fseek(fp, 0, SEEK_SET);
            int ret = convert_findreplace_v16(fp, fo);
            fclose(fp);
            fclose(fo);
            return ret;
        } else if (out) {
            fprintf(stderr, "Error: Use -e 16 to convert FindReplace to iOS \u226416 CFBurstTrie format\n");
            fclose(fo);
            fclose(fp);
            return EXIT_FAILURE;
        }
        fseek(fp, 0, SEEK_SET);
        int ret = read_findreplace(fp);
        fclose(fp);
        return ret;
    }

    int count;
    if ((count32 & 0xFFFF) == 0) {
        intype = 3;
        count = count32 >> 16;
    } else if ((count32 >> 16) == 0) {
        intype = 3;
        count = count32 & 0xFFFF;
    } else {
        count = count32 & 0xFFFF;
        fseek(fp, 2, SEEK_SET);
        if (count >= 2937) {
            intype = 2;
        } else if (count >= 2538) {
            intype = 1;
        } else { // 2028
            intype = 0;
        }
    }
    modern = intype >= 2;
    uint16_t pad = paddings[intype];
    uint16_t opad = out ? paddings[outtype] : 0;
    uint16_t shift = intype == 3 ? 2 : 0;

    printf("Detected file variant: %d\n", intype);
    printf("Emoji count: %d\n", count);
    fread(buf, 2, 1, fp);
    printf("Taiwan flag index: 0x%x\n", buf[0]);

    if (out) {
        fwrite(&count, 2, 1, fo);
        fwrite(&buf, 2, 1, fo);
    }

    uint32_t fs[1];
    fread(fs, 4, 1, fp);
    printf("File size: 0x%x\n", fs[0]);
    if (out) {
        fs[0] -= (pad - opad) * count;
        fs[0] -= shift;
        fwrite(fs, 4, 1, fo);
    }

    uint32_t metaptr = 8;
    uint32_t metaptr_w = 8;
    uint32_t emojiptr_w = metaptr + count * opad;
    uint32_t metaptr_d = pad;
    uint32_t metadata[4]; // iOS 12.1+
    uint16_t metadata_l[7]; // iOS 10.2 - 12.0
    uint16_t metadata_ll[5]; // iOS 10.1.1

    char emoji[64];
    char desc[256];
    std::vector<std::string> desc_w(count);
    int index = 1;
    while (index <= count) {
        fseek(fp, metaptr + shift, SEEK_SET);
        uint32_t emojiptr = 0;
        switch (intype) {
            case 0:
                fread(metadata_ll, sizeof(uint16_t), 5, fp);
                emojiptr = metadata_ll[3];
                break;
            case 1:
                fread(metadata_l, sizeof(uint16_t), 7, fp);
                emojiptr = (metadata_l[4] << 16) | metadata_l[3];
                break;
            case 2:
            case 3:
                fread(metadata, sizeof(uint32_t), 4, fp);
                emojiptr = metadata[2];
                break;
        }
        fseek(fp, emojiptr, SEEK_SET);
        read_str(fp, emoji, sizeof(emoji));
        CFStringRef cemoji = CFStringCreateWithCString(kCFAllocatorDefault, emoji, kCFStringEncodingUTF8);
        if (cemoji) {
            switch (intype) {
                case 2:
                case 3: {
                    uint32_t d0 = metadata[0];
                    uint32_t d1 = metadata[1];
                    uint32_t baseIndex = d1;
                    if (baseIndex >= count)
                        baseIndex = 0;
                    uint32_t descPos = metadata[3];
                    fseek(fp, descPos, SEEK_SET);
                    read_str(fp, desc, sizeof(desc));
                    // [idx] emoji : variant base-idx? str-pos desc-pos (...)
                    // 80000000 0000BF00 C8D00000 E4550100 -> 0x00000080    0x00BF0000      0x0000D0C8      0x000155E4
                    // 60000200 00000000 92000100 E19F0100 -> 0x00020060    0x00000000      0x00010092      0x00019FE1
                    if (out) {
                        switch (outtype) {
                            case 2: {
                                metadata[2] -= shift;
                                metadata[3] -= shift;
                                break;
                            }
                            case 1: {
                                metadata_l[0] = (uint16_t)d0;
                                metadata_l[1] = d1 & 0xFFFF;
                                metadata_l[2] = d1 >> 16;
                                metadata_l[3] = emojiptr_w & 0xFFFF;
                                metadata_l[4] = emojiptr_w >> 16;
                                metadata_l[5] = descPos & 0xFFFF;
                                metadata_l[6] = descPos >> 16;
                                break;
                            }
                            case 0: {
                                metadata_ll[0] = d0;
                                metadata_ll[1] = baseIndex;
                                metadata_ll[2] = d1 >> 16;
                                metadata_ll[3] = emojiptr_w; // WILL OVERFLOW when emojiptr_w > 0xFFFF
                                metadata_ll[4] = descPos; // WILL OVERFLOW when descPos > 0xFFFF
                                break;
                            }
                        }
                        // write metadata
                        fseek(fo, metaptr_w, SEEK_SET);
                        switch (outtype) {
                            case 2:
                                fwrite(metadata, sizeof(uint32_t), 4, fo);
                                break;
                            case 1:
                                fwrite(metadata_l, sizeof(uint16_t), 7, fo);
                                break;
                            case 0:
                                fwrite(metadata_ll, sizeof(uint16_t), 5, fo);
                                break;
                        }
                        // write string
                        fseek(fo, emojiptr_w, SEEK_SET);
                        size_t emojilen = strlen(emoji) + 1;
                        fwrite(emoji, emojilen, 1, fo);
                        emojiptr_w += emojilen;
                        // copy description for later write
                        desc_w[index - 1] = desc;
                        metaptr_w += opad;
                    }
                    if (filter == 0xffffff || filter & d0) {
                        printf("[0x%-3x] %s  :  %08x %08x | [0x%-3x]  [0x%x]  [0x%x]  (skin: %d-%d, base-idx: %x, hair: %d-%d, gender: %c, style: %d, common: %d, desc: %s)\n", index, emoji, d0, d1, baseIndex, emojiptr, descPos, has_skin(d0), baseIndex ? skin_tone(d0) : 0, baseIndex, has_hair(d0), hair_style(d0), gender(d0), presentation_style(d0), is_common(d0), strlen(desc) ? desc : "<none>");
                    }
                    break;
                }
                case 1: {
                    uint16_t d0 = metadata_l[0];
                    uint16_t baseIndex = metadata_l[1];
                    uint16_t d2 = metadata_l[2];
                    uint32_t descPos = (metadata_l[6] << 16) | metadata_l[5];
                    fseek(fp, descPos, SEEK_SET);
                    read_str(fp, desc, sizeof(desc));
                    // [idx] emoji : variant base-idx ?? str-pos desc-pos (...)
                    // 8000 0000 BF00 02980000 8FFC0000 -> 0x0080     0x0000     0x00BF     0x00009802     0x0000FC8F
                    // 2011 840A 0000 D7F80000 2E4E0100 -> 0x1120     0x0A84     0x0000     0x0000F8D7     0x00014E2E
                    printf("[0x%-3x] %s  :  0x%-4x  0x%x  0x%x  [0x%-5x]  [0x%-5x] (skin: %d-%d, base-idx: %x, gender: %c, desc: %s)\n", index, emoji, d0, baseIndex, d2, emojiptr, descPos, has_skin(d0), baseIndex ? skin_tone(d0) : 0, baseIndex, gender(d0), strlen(desc) ? desc : "<none>");
                    break;
                }
                case 0: {
                    uint16_t d0 = metadata_ll[0];
                    uint16_t baseIndex = metadata_ll[1];
                    uint16_t d2 = metadata_ll[2];
                    uint16_t descPos = metadata_ll[4];
                    fseek(fp, descPos, SEEK_SET);
                    read_str(fp, desc, sizeof(desc));
                    // [idx] emoji : variant base-idx ?? str-pos desc-pos
                    // 8000 0000 BF00 404F 1C90 ->  0x0080    0x0000    0x00BF    0x4F40    0x901C
                    printf("[0x%-3x] %s  :  0x%-4x  [0x%x]  0x%x  [0x%x] [0x%x] (skin: %d-%d, base-idx: %x, gender: %c, desc: %s)\n", index, emoji, d0, baseIndex, d2, emojiptr, descPos, has_skin(d0), baseIndex ? skin_tone(d0) : 0, baseIndex, gender(d0), strlen(desc) ? desc : "<none>");
                    break;
                }
            }
            CFRelease(cemoji);
        }
        ++index;
        metaptr += metaptr_d;
    }

    if (out) {
        index = 1;
        metaptr_w = 8;
        uint32_t descPos_w = emojiptr_w;
        uint16_t offset = 0;
        switch (outtype) {
            case 2:
                offset = 12;
                break;
            case 1:
                offset = 10;
                break;
            case 0:
                offset = 8;
                break;
        }
        while (index <= count) {
            // write description
            fseek(fo, descPos_w, SEEK_SET);
            size_t desclen = desc_w[index - 1].size() + 1;
            fwrite(desc_w[index - 1].c_str(), desclen, 1, fo);
            // update metadata description position
            fseek(fo, metaptr_w + offset, SEEK_SET);
            fwrite(&descPos_w, outtype == 0 ? sizeof(uint16_t) : sizeof(uint32_t), 1, fo);
            descPos_w += desclen;
            metaptr_w += opad;
            ++index;
        }
        if (outtype == 0) {
            // iOS 10.1.1 cannot read more than MAX_EMOJI_IOS_10_1_1 emojis
            fseek(fo, 0, SEEK_SET);
            fwrite(&MAX_EMOJI_IOS_10_1_1, 2, 1, fo);
        }
        fclose(fo);
    }

    fclose(fp);
    return EXIT_SUCCESS;
}
