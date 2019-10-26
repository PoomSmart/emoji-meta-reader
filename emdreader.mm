#include <stdio.h>
#include <stdlib.h>

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

/* bool gender_like(uint32_t d0) {
    return d0 & 0x4;
} */

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

int main(int argc, char *argv[], char *envp[]) {
    if (argc != 3 && argc != 4) {
        printf("Usage: emdreader [0/1] <path-to-metadata-dat>\n");
        printf("Usage: emdreader 1 <input-dat> <output-dat>\n");
        printf("1 = modern dat, 0 = legacy dat\n");
        return EXIT_FAILURE;
    }
    modern = atoi(argv[1]) == 1;
    uint16_t buf[1];
    FILE *fp, *fo;
    const char *filename = argv[2];

    if ((fp = fopen(filename, "rb")) == NULL) {
        printf("Unable to open file for read: %s\n", filename);
        return EXIT_FAILURE;
    }
    bool out = argc == 4;
    if (out && (fo = fopen(argv[3], "wb+")) == NULL) {
        printf("Unable to open file for write: %s\n", argv[3]);
        return EXIT_FAILURE;
    }
    if (out && strcmp(filename, argv[3]) == 0) {
        printf("Input file and output file cannot be the same\n");
        return EXIT_FAILURE;
    }

    fread(buf, 2, 1, fp);
    int count = buf[0];
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
        fs[0] -= (16 - 14) * count;
        fwrite(fs, 4, 1, fo);
    }

    uint16_t metaptr = 8;
    uint16_t metaptr_w = 8;
    uint32_t emojiptr_w = metaptr + count * 14;
    uint16_t metaptr_d = modern ? 16 : 14;
    uint32_t metadata[4];
    uint16_t metadata_l[7];

    char emoji[64];
    char desc[256];
    char desc_w[count][256];
    int16_t index = 1;
    while (index <= count) {
        fseek(fp, metaptr, SEEK_SET);
        if (modern)
            fread(metadata, sizeof(uint32_t), 4, fp);
        else
            fread(metadata_l, sizeof(uint16_t), 7, fp);
        uint32_t emojiptr = modern ? metadata[2] : ((metadata_l[4] << 16) | metadata_l[3]);
        fseek(fp, emojiptr, SEEK_SET);
        read_str(fp, emoji);
        CFStringRef cemoji = CFStringCreateWithCString(kCFAllocatorDefault, emoji, kCFStringEncodingUTF8);
        if (cemoji) {
            if (modern) {
                uint32_t d0 = metadata[0];
                uint32_t baseIndex = metadata[1];
                if (baseIndex >= count)
                    baseIndex = 0;
                uint32_t descPos = metadata[3];
                fseek(fp, descPos, SEEK_SET);
                read_str(fp, desc);
                // [idx] emoji : variant base-idx? str-pos desc-pos (...)
                // 80000000 0000BF00 C8D00000 E4550100 -> 0x00000080    0x00BF0000      0x0000D0C8      0x000155E4
                // 60000200 00000000 92000100 E19F0100 -> 0x00020060    0x00000000      0x00010092      0x00019FE1
                if (out) {
                    metadata_l[0] = (uint16_t)d0;
                    metadata_l[1] = baseIndex;
                    metadata_l[2] = 0;
                    metadata_l[3] = emojiptr_w & 0xFFFF;
                    metadata_l[4] = emojiptr_w >> 16;
                    metadata_l[5] = descPos & 0xFFFF;
                    metadata_l[6] = descPos >> 16;
                    // write metadata
                    fseek(fo, metaptr_w, SEEK_SET);
                    fwrite(metadata_l, sizeof(uint16_t), 7, fo);
                    // write string
                    fseek(fo, emojiptr_w, SEEK_SET);
                    size_t emojilen = strlen(emoji) + 1;
                    fwrite(emoji, emojilen, 1, fo);
                    emojiptr_w += emojilen;
                    // copy description for later write
                    strcpy(desc_w[index - 1], desc);
                    metaptr_w += 14;
                }
                NSLog(@"[0x%-3x] %@  :  0x%-10x  [0x%-3x]  [0x%x]  [0x%x]  (skin: %d-%d, base-idx: %x, hair: %d-%d, gender: %c, style: %d, common: %d, desc: %s)\n", index, cemoji, d0, baseIndex, emojiptr, descPos, has_skin(d0), baseIndex ? skin_tone(d0) : 0, baseIndex, has_hair(d0), hair_style(d0), gender(d0), presentation_style(d0), is_common(d0), strlen(desc) ? desc : "<none>");
            } else {
                uint16_t d0 = metadata_l[0];
                uint16_t baseIndex = metadata_l[1];
                uint16_t d2 = metadata_l[2];
                uint32_t descPos = (metadata_l[6] << 16) | metadata_l[5];
                fseek(fp, descPos, SEEK_SET);
                read_str(fp, desc);
                // [idx] emoji : variant base-idx ?? str-pos desc-pos (...)
                // 8000 0000 BF00 02980000 8FFC0000 -> 0x0080     0x0000     0x00BF     0x00009802     0x0000FC8F
                // 2011 840A 0000 D7F80000 2E4E0100 -> 0x1120     0x0A84     0x0000     0x0000F8D7     0x00014E2E
                NSLog(@"[0x%-3x] %@  :  0x%-4x  0x%x  0x%x  [0x%-5x]  [0x%-5x] (skin: %d-%d, base-idx: %x, gender: %c, desc: %s)\n", index, cemoji, d0, baseIndex, d2, emojiptr, descPos, has_skin(d0), baseIndex ? skin_tone(d0) : 0, baseIndex, gender(d0), strlen(desc) ? desc : "<none>");
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
        while (index <= count) {
            // write description
            fseek(fo, descPos_w, SEEK_SET);
            size_t desclen = strlen(desc_w[index - 1]) + 1;
            fwrite(desc_w[index - 1], desclen, 1, fo);
            // update metadata description position
            fseek(fo, metaptr_w + 10, SEEK_SET);
            fwrite(&descPos_w, sizeof(uint32_t), 1, fo);
            descPos_w += desclen;
            metaptr_w += 14;
            ++index;
        }
        fclose(fo);
    }

    fclose(fp);
    return EXIT_SUCCESS;
}
