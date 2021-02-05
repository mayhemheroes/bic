#include "lang.h"

static void outputFFITypes(const struct lang &lang)
{
    FILE *f = fopen("ffi-types.c", "w");

    fputs("/*\n"
          " * ffi-types.c - match a tree ctype to an ffi type.\n"
          " *\n"
          " * automatically generated by genffitypes. do not edit.\n"
          " */\n\n"
          " #include \"ffi-types.h\"\n"
          "\n"
          "ffi_type *get_ffi_type(enum tree_type ctype)\n"
          "{\n"
          "    switch(ctype) {\n", f);

    for (auto const &ctype : lang.treeCTypes)
      fprintf(f, "    case %s:\n"
                 "        return &%s;\n", ctype.name.c_str(), ctype.ffi_type.c_str());

    fputs("    default:\n"
          "         fprintf(stderr, \"Error: could not resolve ctype into ffi type.\\n\");\n"
          "         exit(1);\n"
          "    }\n"
          "}\n", f);

    fclose(f);
}

static void usage(char *progname)
{
    fprintf(stderr, "%s - Generate the `ffi_types.h' and `ffi_types.c' files from a language description\n",
            progname);
    fprintf(stderr, "Usage: %s LANG_DESC_FILE\n", progname);
    fprintf(stderr, "\n");
    fprintf(stderr, "Where LANG_DESC_FILE is a language description file.\n");
}

int main(int argc, char *argv[])
{
    struct lang lang;
    FILE *f;

    if (argc != 2) {
        fprintf(stderr, "Error: %s expects exactly one argument\n", argv[0]);
        usage(argv[0]);
        return 1;
    }

    f = fopen(argv[1], "r");

    if (!f) {
        perror("Could not open lang file");
        usage(argv[0]);
        exit(2);
    }

    lang_read(f, lang);

    outputFFITypes(lang);

    return 0;
}
