# Shim for LT_SYS_SYMBOL_USCORE, which libtool >= 2.5 dropped (bic's configure.ac
# still calls it). On Linux/ELF compiled symbols carry no leading underscore, so
# record that; this reproduces what real libtool determined on this platform.
AC_DEFUN([LT_SYS_SYMBOL_USCORE], [sys_symbol_underscore=no])
