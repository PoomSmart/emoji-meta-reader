#include <stdio.h>
#include <stdlib.h>

bool modern = false;

bool hasSkin(uint32_t d0) {
    return d0 & 0x40;
}

// TODO: correct?
bool isCommon(uint32_t d0) {
    return d0 & 0x80;
}

int skinTone(uint32_t d0) {
    return modern ? ((d0 >> 20) & 0xF) : d0 >> 12;
}

bool hasHair(uint32_t d0) {
    return d0 & 0x100;
}

int hairStyle(uint32_t d0) {
    return d0 >> 24;
}

// TODO: correct?
int presentationStyle(uint32_t d0) {
    if (d0 & 0x20)
        return 1;
    if (d0 & 0x10)
        return 2;
    return 0;
}

/* bool genderLike(uint32_t d0) {
    return d0 & 0x04;
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

void readStr(FILE *fp, char *str) {
    char b;
    size_t n = 0;
    while ((b = fgetc(fp)) != EOF && b != '\0')
        str[n++] = (unsigned char)b;
    str[n] = '\0';
}

int main(int argc, char *argv[], char *envp[]) {
    if (argc != 2) {
        printf("Usage: emdreader <path-to-metadata-dat>\n");
        return EXIT_FAILURE;
    }
    unsigned char buf[2];
    FILE *fp;
    const char *filename = argv[1];

    if ((fp = fopen(filename, "rb")) == NULL) {
        printf("Unable to open file: %s\n", filename);
        return EXIT_FAILURE;
    }

    fread(buf, 2, 1, fp);
    int count = (buf[1] << 8) | buf[0];
    printf("Emoji count: %d\n", count);
    modern = count >= 3000;
    int16_t eptr = (buf[0] << 8) | buf[1];
    uint16_t reptr = ((eptr & 0xf) << 12) | ((eptr & 0xf0) << 4) | ((eptr & 0xf00) >> 4) | ((eptr & 0xf000) >> 12);
    printf("Emoji string pointer: %x\n", reptr);
    fread(buf, 2, 1, fp);
    printf("Taiwan flag index: %u\n", buf[0]); // TODO: is it?

    // unknown 4 bytes skipped
    uint16_t metaptr = 8;
    uint16_t metaptr_d = modern ? 16 : 14;
    uint32_t metadata[4];
    uint16_t metadata_l[7];

    char emoji[64];
    char desc[256];
    int16_t index = 1;
    while (index <= count) {
        fseek(fp, metaptr, SEEK_SET);
        if (modern)
            fread(metadata, sizeof(uint32_t), 4, fp);
        else
            fread(metadata_l, sizeof(uint16_t), 7, fp);
        uint32_t emojiptr = modern ? metadata[2] : metadata_l[3];
        fseek(fp, emojiptr, SEEK_SET);
        readStr(fp, emoji);
        CFStringRef cemoji = CFStringCreateWithCString(kCFAllocatorDefault, emoji, kCFStringEncodingUTF8);
        if (cemoji) {
            if (modern) {
                uint32_t d0 = metadata[0];
                uint32_t baseIndex = metadata[1];
                if (baseIndex >= count)
                    baseIndex = 0;
                uint32_t descPos = metadata[3];
                fseek(fp, descPos, SEEK_SET);
                readStr(fp, desc);
                if (!strlen(desc))
                    strcpy(desc, "<none>");
                // [idx] emoji : variant base-idx? str-pos desc-pos (...)
                NSLog(@"[0x%-3x] %@  :  0x%-10x  [0x%-3x]  [0x%x]  [0x%x]  (skin: %d-%d, base-idx: %x, hair: %d-%d, gender: %c, style: %d, common: %d, desc: %s)\n", index, cemoji, d0, baseIndex, emojiptr, descPos, hasSkin(d0), baseIndex ? skinTone(d0) : 0, baseIndex, hasHair(d0), hairStyle(d0), gender(d0), presentationStyle(d0), isCommon(d0), desc);
            } else {
                uint16_t d0 = metadata_l[0];
                uint16_t baseIndex = metadata_l[1];
                uint16_t d2 = metadata_l[2];
                uint16_t d4 = metadata_l[4];
                uint32_t descPos = (metadata_l[6] << 16) | metadata_l[5];
                fseek(fp, descPos, SEEK_SET);
                readStr(fp, desc);
                if (!strlen(desc))
                    strcpy(desc, "<none>");
                // [idx] emoji : variant base-idx ?? str-pos ?? desc-pos (...)
                NSLog(@"[0x%-3x] %@  :  0x%-4x  0x%x  0x%x  [0x%-5x]  0x%x  [0x%-5x] (skin: %d-%d, base-idx: %x, gender: %c, desc: %s)\n", index, cemoji, d0, baseIndex, d2, emojiptr, d4, descPos, hasSkin(d0), baseIndex ? skinTone(d0) : 0, baseIndex, gender(d0), desc);
            }
            CFRelease(cemoji);
        }
        ++index;
        metaptr += metaptr_d;
    }

    fclose(fp);
    return EXIT_SUCCESS;
}
