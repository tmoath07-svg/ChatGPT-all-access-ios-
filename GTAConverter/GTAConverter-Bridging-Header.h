#include <stdint.h>
#include <stddef.h>

const char *gta_engine_version(void);
char *gta_engine_probe_rpf(const char *path);
char *gta_engine_list_rpf(const char *path);
char *gta_engine_preview_vehicle_model(const char *path);
char *gta_engine_build_rpf7(const char *input_directory, const char *output_file);
char *gta_engine_convert_and_build_rpf(const char *input_directory, const char *output_file);
char *gta_engine_convert_resource(const char *input_path, const char *output_directory);
char *gta_engine_convert_folder(const char *input_directory, const char *output_directory);
char *gta_engine_convert_fivem_resource(const char *input_directory, const char *output_directory);
char *gta_engine_extract_ytd(const char *input_path, const char *output_directory);
char *gta_engine_build_ytd(const char *input_directory, const char *output_file);
void gta_engine_free_string(char *value);

char *gta_ftp_connect(const char *host, uint16_t port, const char *username, const char *password);
char *gta_ftp_list(const char *host, uint16_t port, const char *username, const char *password, const char *remote_path);
char *gta_ftp_mkdir(const char *host, uint16_t port, const char *username, const char *password, const char *remote_path, const char *folder_name);
char *gta_ftp_upload(const char *host, uint16_t port, const char *username, const char *password, const char *remote_path, const char *remote_name, const char *local_path);
char *gta_ftp_download(const char *host, uint16_t port, const char *username, const char *password, const char *remote_path, const char *remote_name, const char *local_path);
