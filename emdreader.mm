#include <stdio.h>
#include <stdlib.h>

bool hasSkin(uint32_t v) {
    return v & 0x40;
}

int skinTone(uint32_t v) {
    return hasSkin(v) ? 0 : MAX(2, v >> 20) - 1;
}

bool hasHair(uint32_t v) {
    return v & 0x100;
}

int hairStyle(uint32_t v) {
    return v & 0xF;
}

// TODO: correct?
int presentationStyle(uint32_t v) {
    if (v & 0x20)
        return 1;
    if (v & 0x10)
        return 2;
    return 0;
}

char gender(uint32_t v) {
    if (v & 0x20000)
        return 'F';
    if (v & 0x10000)
        return 'M';
    return '-';
}

void readStr(FILE *fp, char *emoji) {
    char b;
    size_t n = 0;
    while ((b = fgetc(fp)) != EOF && b != '\0')
        emoji[n++] = (unsigned char)b;
    emoji[n] = '\0';
}

// TODO: Support iOS < 12.1 emoji metadata ?
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
    int16_t eptr = (buf[0] << 8) | buf[1];
    uint16_t reptr = ((eptr & 0xf) << 12) | ((eptr & 0xf0) << 4) | ((eptr & 0xf00) >> 4) | ((eptr & 0xf000) >> 12);
    printf("Emoji string pointer: %x\n", reptr);
    fread(buf, 2, 1, fp);
    printf("Taiwan flag index: %u\n", buf[0]); // TODO: is it?

    // unknown 3 bytes skipped
    uint16_t metaptr = 7;
    uint32_t metadata[4];

    char emoji[64];
    char desc[256];
    int16_t index = 1;
    while (index <= count) {
        fseek(fp, metaptr, SEEK_SET);
        fread(metadata, sizeof(uint32_t), 4, fp);
        uint32_t emojiptr = metadata[2] >> 8;
        fseek(fp, emojiptr, SEEK_SET);
        readStr(fp, emoji);
        CFStringRef cemoji = CFStringCreateWithCString(kCFAllocatorDefault, emoji, kCFStringEncodingUTF8);
        if (cemoji) {
            uint32_t d0 = metadata[0] >> 8;
            uint32_t d1 = metadata[1];
            uint32_t descPos = metadata[3] >> 8;
            fseek(fp, descPos, SEEK_SET);
            readStr(fp, desc);
            if (!strlen(desc))
                strcpy(desc, "<none>");
            // emoji : variant meta(+) str-pos desc-pos (...)
            NSLog(@"%@  :  0x%-10x  0x%-8x  [0x%x]  [0x%x]  (skin: %d-%d, hair: %d-%d, gender: %c, style: %d, desc: %s)\n", cemoji, d0, d1, emojiptr, descPos, hasSkin(d0), skinTone(d0), hasHair(d0), hairStyle(d1), gender(d0), presentationStyle(d0), desc);
            CFRelease(cemoji);
        }
        ++index;
        metaptr += 16;
    }

    fclose(fp);
    return EXIT_SUCCESS;
}
