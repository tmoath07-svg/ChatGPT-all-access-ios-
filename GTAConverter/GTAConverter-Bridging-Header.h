#include <stdint.h>
#include <stddef.h>

const char *gta_engine_version(void);
char *gta_engine_probe_rpf(const char *path);
char *gta_engine_build_rpf7(const char *input_directory, const char *output_file);
char *gta_engine_convert_resource(const char *input_path, const char *output_directory);
void gta_engine_free_string(char *value);
