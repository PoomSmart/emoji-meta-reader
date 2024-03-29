#include <cstdlib>
#include <cstring>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#import <CoreFoundation/CoreFoundation.h>

bool modern = false;

bool has_skin(uint32_t d0) {
    return d0 & 0x40;
}

// TODO: correct?
bool is_common(uint32_t d0) {
    return d0 & 0x80;
}

int skin_tone(uint32_t d0) {
    return modern ? ((d0 >> 20) & 0xF) : d0 >> 12;
}

bool has_hair(uint32_t d0) {
    return d0 & 0x100;
}

int hair_style(uint32_t d0) {
    return d0 >> 24;
}

// TODO: correct?
int presentation_style(uint32_t d0) {
    if (d0 & 0x20)
        return 1;
    if (d0 & 0x10)
        return 2;
    return 0;
}

char gender(uint32_t d0) {
    if (modern) {
        if (d0 & 0x20000)
            return 'F';
        if (d0 & 0x10000)
            return 'M';
    } else {
        if (d0 & 0x200)
            return 'F';
        if (d0 & 0x100)
            return 'M';
    }
    return '-';
}

void read_str(FILE *fp, char *str) {
    char b;
    size_t n = 0;
    while ((b = fgetc(fp)) != EOF && b != '\0')
        str[n++] = (unsigned char)b;
    str[n] = '\0';
}

bool is_valid_mode(int m) {
    return m == 0 || m == 1 || m == 2 || m == 3;
}

void usage() {
    printf("Usage: emdreader -i <path-to-metadata-dat>\n");
    printf("Usage: emdreader -i <input-dat> -e <export-mode> -o <output-dat>\n");
    printf("Mode: 3 = iOS 17.0+, 2 = iOS 12.1 - 16.7, 1 = pre-iOS 12.1, 0 = iOS 10.1.1\n");
}

int main(int argc, char *argv[], char *envp[]) {
    int opt;
    int intype = -1;
    int outtype = -1;
    int filter = 0xffffff;
    FILE *fp, *fo;
    bool out = false;
    while ((opt = getopt(argc, argv, "i:o:e:f:h")) != -1) {
        switch (opt) {
            case 'e':
                outtype = atoi(strdup(optarg));
                break;
            case 'i': {
                const char *infile = strdup(optarg);
                if ((fp = fopen(infile, "rb")) == NULL) {
                    printf("Unable to open file for read\n");
                    return EXIT_FAILURE;
                }
                break;
            }
            case 'o': {
                const char *outfile = strdup(optarg);
                fo = fopen(outfile, "wb+");
                break;
            }
            case 'f': {
                filter = strtoul(strdup(optarg), NULL, 16);
                break;
            }
            case 'h':
                usage();
                return EXIT_SUCCESS;
        }
    }

    if (is_valid_mode(outtype)) {
        if (fo == NULL) {
            printf("Unable to open file for write\n");
            return EXIT_FAILURE;
        }
        out = true;
    }

    uint16_t buf[1];
    uint16_t paddings[] = { 10, 14, 16, 16 };

    fread(buf, 2, 1, fp);
    int count = buf[0];
    if (count >= 2937) {
        intype = 2;
    } else if (count >= 2538) {
        intype = 1;
    } else if (count == 0) { 
        intype = 3;
        fread(buf, 2, 1, fp);
        count = buf[0];
    } else { // 2028
        intype = 0;
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

    uint16_t metaptr = 8;
    uint16_t metaptr_w = 8;
    uint32_t emojiptr_w = metaptr + count * opad;
    uint16_t metaptr_d = pad;
    uint32_t metadata[4]; // iOS 12.1+
    uint16_t metadata_l[7]; // iOS 10.2 - 12.0
    uint16_t metadata_ll[5]; // iOS 10.1.1

    char emoji[64];
    char desc[256];
    char desc_w[count][256];
    int16_t index = 1;
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
        read_str(fp, emoji);
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
                    read_str(fp, desc);
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
                        strcpy(desc_w[index - 1], desc);
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
                    read_str(fp, desc);
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
                    read_str(fp, desc);
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
            size_t desclen = strlen(desc_w[index - 1]) + 1;
            fwrite(desc_w[index - 1], desclen, 1, fo);
            // update metadata description position
            fseek(fo, metaptr_w + offset, SEEK_SET);
            fwrite(&descPos_w, outtype == 0 ? sizeof(uint16_t) : sizeof(uint32_t), 1, fo);
            descPos_w += desclen;
            metaptr_w += opad;
            ++index;
        }
        if (outtype == 0) {
            // iOS 10.1.1 cannot read more than 3206 emojis
            fseek(fo, 0, SEEK_SET);
            int max_10_1_1 = 3206;
            fwrite(&max_10_1_1, 2, 1, fo);
        }
        fclose(fo);
    }

    fclose(fp);
    return EXIT_SUCCESS;
}
