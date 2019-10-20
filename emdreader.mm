#include <stdio.h>
#include <stdlib.h>

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
	fseek(fp, reptr + 8, SEEK_SET);

	// [ F09F 9880 ] 00 [ F0 9F98 AC ] 00 F09F 9881 00F0 9F98 8200 F09F 9883 ...

	char hexstr[64];
	int16_t index = 1;
	char b;
	while (index <= count) {
		size_t n = 0;
		while ((b = fgetc(fp)) != EOF && b != '\0')
    		hexstr[n++] = (unsigned char)b;
		hexstr[n] = '\0';
		CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, hexstr, kCFStringEncodingUTF8);
		if (str) {
			NSLog(@"%@", str);
			CFRelease(str);
		}
		++index;
	}

	fclose(fp);
	return EXIT_SUCCESS;
}
