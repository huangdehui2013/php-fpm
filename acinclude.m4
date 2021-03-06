
AC_DEFUN([AC_FPM_CHECK_FUNC],
[
	SAVED_CFLAGS="$CFLAGS"
	CFLAGS="$CFLAGS $2"
	SAVED_LIBS="$LIBS"
	LIBS="$LIBS $3"

	AC_CHECK_FUNC([$1],[$4],[$5])

	CFLAGS="$SAVED_CFLAGS"
	LIBS="$SAVED_LIBS"
])

AC_DEFUN([AC_FPM_LIBXML],
[
	AC_MSG_RESULT([checking for XML configuration])

	AC_ARG_WITH([xml-config], AC_HELP_STRING([--with-xml-config=PATH], [path to xml-config]),
		[XMLCONFIG="$withval"],
		[AC_PATH_PROGS(XMLCONFIG, [xml2-config xml-config], "")]
	)

	if test "x$XMLCONFIG" = "x"; then
		AC_MSG_ERROR([XML configuration could not be found])
	else
        AC_MSG_CHECKING([for libxml library])

		if test ! -x "$XMLCONFIG"; then
			AC_MSG_ERROR([$XMLCONFIG cannot be executed])
		fi

		LIBXML_LIBS="`$XMLCONFIG --libs`"
		LIBXML_CFLAGS="`$XMLCONFIG --cflags`"
		LIBXML_VERSION="`$XMLCONFIG --version`"

        AC_MSG_RESULT([yes, $LIBXML_VERSION])

		AC_FPM_CHECK_FUNC([xmlParseFile], [$LIBXML_CFLAGS], [$LIBXML_LIBS], ,
			[AC_MSG_ERROR([Failed to link with libxml])])

		AC_DEFINE(HAVE_LIBXML, 1, [do we have libxml?])
	fi
])

AC_DEFUN([AC_FPM_CLOCK],
[
	have_clock_gettime=no

	AC_MSG_CHECKING([for clock_gettime])

	AC_TRY_LINK([ #include <time.h> ], [struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);], [
		have_clock_gettime=yes
		AC_MSG_RESULT([yes])
	], [
		AC_MSG_RESULT([no])
	])

	if test "$have_clock_gettime" = "no"; then
		AC_MSG_CHECKING([for clock_gettime in -lrt])

		SAVED_LIBS="$LIBS"
		LIBS="$LIBS -lrt"

		AC_TRY_LINK([ #include <time.h> ], [struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);], [
			have_clock_gettime=yes
			AC_MSG_RESULT([yes])
		], [
			LIBS="$SAVED_LIBS"
			AC_MSG_RESULT([no])
		])
	fi

	if test "$have_clock_gettime" = "yes"; then
		AC_DEFINE([HAVE_CLOCK_GETTIME], 1, [do we have clock_gettime?])
	fi

	have_clock_get_time=no

	if test "$have_clock_gettime" = "no"; then
		AC_MSG_CHECKING([for clock_get_time])

		AC_TRY_RUN([ #include <mach/mach.h>
			#include <mach/clock.h>
			#include <mach/mach_error.h>

			int main()
			{
				kern_return_t ret; clock_serv_t aClock; mach_timespec_t aTime;
				ret = host_get_clock_service(mach_host_self(), REALTIME_CLOCK, &aClock);

				if (ret != KERN_SUCCESS) {
					return 1;
				}

				ret = clock_get_time(aClock, &aTime);
				if (ret != KERN_SUCCESS) {
					return 2;
				}

				return 0;
			}
		], [
			have_clock_get_time=yes
			AC_MSG_RESULT([yes])
		], [
			AC_MSG_RESULT([no])
		])
	fi

	if test "$have_clock_get_time" = "yes"; then
		AC_DEFINE([HAVE_CLOCK_GET_TIME], 1, [do we have clock_get_time?])
	fi
])

AC_DEFUN([AC_FPM_TRACE],
[
	have_ptrace=no
	have_broken_ptrace=no

	AC_MSG_CHECKING([for ptrace])

	AC_TRY_COMPILE([
		#include <sys/types.h>
		#include <sys/ptrace.h> ], [ptrace(0, 0, (void *) 0, 0);], [
		have_ptrace=yes
		AC_MSG_RESULT([yes])
	], [
		AC_MSG_RESULT([no])
	])

	if test "$have_ptrace" = "yes"; then
		AC_MSG_CHECKING([whether ptrace works])

		AC_TRY_RUN([
			#include <unistd.h>
			#include <signal.h>
			#include <sys/wait.h>
			#include <sys/types.h>
			#include <sys/ptrace.h>
			#include <errno.h>

			#if !defined(PTRACE_ATTACH) && defined(PT_ATTACH)
			#define PTRACE_ATTACH PT_ATTACH
			#endif

			#if !defined(PTRACE_DETACH) && defined(PT_DETACH)
			#define PTRACE_DETACH PT_DETACH
			#endif

			#if !defined(PTRACE_PEEKDATA) && defined(PT_READ_D)
			#define PTRACE_PEEKDATA PT_READ_D
			#endif

			int main()
			{
				long v1 = (unsigned int) -1; /* copy will fail if sizeof(long) == 8 and we've got "int ptrace()" */
				long v2;
				pid_t child;
				int status;

				if ( (child = fork()) ) { /* parent */
					int ret = 0;

					if (0 > ptrace(PTRACE_ATTACH, child, 0, 0)) {
						return 1;
					}

					waitpid(child, &status, 0);

			#ifdef PT_IO
					struct ptrace_io_desc ptio = {
						.piod_op = PIOD_READ_D,
						.piod_offs = &v1,
						.piod_addr = &v2,
						.piod_len = sizeof(v1)
					};

					if (0 > ptrace(PT_IO, child, (void *) &ptio, 0)) {
						ret = 1;
					}
			#else
					errno = 0;

					v2 = ptrace(PTRACE_PEEKDATA, child, (void *) &v1, 0);

					if (errno) {
						ret = 1;
					}
			#endif
					ptrace(PTRACE_DETACH, child, (void *) 1, 0);

					kill(child, SIGKILL);

					return ret ? ret : (v1 != v2);
				}
				else { /* child */
					sleep(10);
					return 0;
				}
			}
		], [
			AC_MSG_RESULT([yes])
		], [
			have_ptrace=no
			have_broken_ptrace=yes
			AC_MSG_RESULT([no])
		])
	fi

	if test "$have_ptrace" = "yes"; then
		AC_DEFINE([HAVE_PTRACE], 1, [do we have ptrace?])
	fi

	have_mach_vm_read=no

	if test "$have_broken_ptrace" = "yes"; then
		AC_MSG_CHECKING([for mach_vm_read])

		AC_TRY_COMPILE([ #include <mach/mach.h>
			#include <mach/mach_vm.h>
		], [
			mach_vm_read((vm_map_t)0, (mach_vm_address_t)0, (mach_vm_size_t)0, (vm_offset_t *)0, (mach_msg_type_number_t*)0);
		], [
			have_mach_vm_read=yes
			AC_MSG_RESULT([yes])
		], [
			AC_MSG_RESULT([no])
		])
	fi

	if test "$have_mach_vm_read" = "yes"; then
		AC_DEFINE([HAVE_MACH_VM_READ], 1, [do we have mach_vm_read?])
	fi

	proc_mem_file=""

	if test -r /proc/$$/mem ; then
		proc_mem_file="mem"
	else
		if test -r /proc/$$/as ; then
			proc_mem_file="as"
		fi
	fi

	if test -n "$proc_mem_file" ; then
		AC_MSG_CHECKING([for proc mem file])

		AC_TRY_RUN([
			#define _GNU_SOURCE
			#define _FILE_OFFSET_BITS 64
			#if HAVE_INTTYPES_H
			#include <inttypes.h>
			#else
			#include <stdint.h>
			#endif

			#include <unistd.h>
			#include <sys/types.h>
			#include <sys/stat.h>
			#include <fcntl.h>
			#include <stdio.h>
			int main()
			{
				long v1 = (unsigned int) -1, v2 = 0;
				char buf[128];
				int fd;
				sprintf(buf, "/proc/%d/$proc_mem_file", getpid());
				fd = open(buf, O_RDONLY);
				if (0 > fd) {
					return 1;
				}
				if (sizeof(long) != pread(fd, &v2, sizeof(long), (uintptr_t) &v1)) {
					close(fd);
					return 1;
				}
				close(fd);
				return v1 != v2;
			}
		], [
			AC_MSG_RESULT([$proc_mem_file])
		], [
			proc_mem_file=""
			AC_MSG_RESULT([no])
		])
	fi

	if test -n "$proc_mem_file"; then
		AC_DEFINE_UNQUOTED([PROC_MEM_FILE], "$proc_mem_file", [/proc/pid/mem interface])
	fi

	use_ptrace=no
	use_pread=no
	use_mach=no

	if test "$have_ptrace" = "yes"; then
		use_ptrace=yes
	elif test -n "$proc_mem_file"; then
		use_pread=yes
	elif test "$have_mach_vm_read" = "yes" ; then
		use_mach=yes
	fi

	AM_CONDITIONAL(FPM_TRACE_USE_PTRACE, test "x$use_ptrace" = "xyes")
	AM_CONDITIONAL(FPM_TRACE_USE_PREAD, test "x$use_pread" = "xyes")
	AM_CONDITIONAL(FPM_TRACE_USE_MACH, test "x$use_mach" = "xyes")
])

AC_DEFUN([AC_FPM_PRCTL],
[
	AC_MSG_CHECKING([for prctl])

	AC_TRY_COMPILE([ #include <sys/prctl.h> ], [prctl(0, 0, 0, 0, 0);], [
		AC_DEFINE([HAVE_PRCTL], 1, [do we have prctl?])
		AC_MSG_RESULT([yes])
	], [
		AC_MSG_RESULT([no])
	])
])

m4_include([m4/ac_php_frag.m4])
m4_include([m4/ac_lib_event.m4])

AC_DEFUN([AC_FPM_PHP],
[
	AC_ARG_WITH([php-src], AC_HELP_STRING([--with-php-src=DIR], [full path to php source dir]))

	AC_ARG_WITH([php-build], AC_HELP_STRING([--with-php-build=DIR], [full path to php build dir, only needed if differ from source dir]))

	AC_MSG_CHECKING([for php configuration])

	if test -z "$with_php_src" -o "$with_php_src" = "no" -o "$with_php_src" = "yes" ; then
		AC_MSG_ERROR([Please specify full path to php source dir: --with-php=DIR])
	else
		PHP_SRCDIR="`cd $with_php_src; pwd`"
	fi

	if test ! -f $PHP_SRCDIR/main/php.h ; then
		AC_MSG_ERROR([No php sources found in php source dir])
	fi

	if test -z "$with_php_build" -o "$with_php_build" = "no" -o "$with_php_build" = "yes" ; then
		PHP_BUILDDIR="$PHP_SRCDIR"
	else
		PHP_BUILDDIR="`cd $with_php_build; pwd`"
	fi

	if test ! -f $PHP_BUILDDIR/Makefile ; then
		AC_MSG_ERROR([No Makefile found in php build dir. Did you run configure ?])
		AC_MSG_ERROR([Use command: cd $php_src_dir && ./configure && make])
		AC_MSG_ERROR([If you have separate php build dir, please specify it --with-php-build=DIR])
	fi

	PHP_GLOBAL_OBJS=`grep "^PHP_GLOBAL_OBJS =" $PHP_BUILDDIR/Makefile | sed -e 's,.*= ,,'`
	PHP_EXTRA_LIBS=`grep "^EXTRA_LIBS =" $PHP_BUILDDIR/Makefile | sed -e 's,.*= ,,'`
	PHP_VERSION=`grep "^PHP_VERSION =" $PHP_BUILDDIR/Makefile | sed -e 's,.*= ,,'`
	PHP_SAPI=`grep "^PHP_SAPI =" $PHP_BUILDDIR/Makefile | sed -e 's,.*= ,,'`

	if test -z "$PHP_GLOBAL_OBJS" ; then
		AC_MSG_ERROR([Cannot find expected makefile variables])
	fi

	AC_MSG_RESULT([$PHP_VERSION])

	# sanity check
	if test "$PHP_SAPI" != "cgi" ; then
		AC_MSG_WARN([PHP was built as sapi \"$PHP_SAPI\". Its recommended to buid php without any sapi-related switches.])
	fi

	PHP_OBJS="$PHP_GLOBAL_OBJS main/internal_functions.lo"

	AC_SUBST(PHP_OBJS)
	AC_SUBST(PHP_SRCDIR)
	AC_SUBST(PHP_BUILDDIR)
	AC_SUBST(PHP_VERSION)
])

AC_DEFUN([AC_FPM_PATHS],
[

	AC_ARG_WITH([fpm-bin],
		AC_HELP_STRING([--with-fpm-bin=@<:@PATH@:>@], [Set the path for php-fpm binary @<:@/usr/local/bin/php-fpm@:>@]))

	AC_ARG_WITH([fpm-port],
		AC_HELP_STRING([--with-fpm-port=@<:@PORT@:>@], [Set the tcp port number to listen for cgi requests @<:@9000@:>@]))

	AC_ARG_WITH([fpm-conf],
		AC_HELP_STRING([--with-fpm-conf=@<:@PATH@:>@], [Set the path for php-fpm configuration file @<:@/etc/php-fpm.conf@:>@]))

	AC_ARG_WITH([fpm-init],
		AC_HELP_STRING([--with-fpm-init=@<:@PATH@:>@], [Set the path for php-fpm init file @<:@/etc/init.d/php-fpm@:>@]))

	AC_ARG_WITH([fpm-log],
		AC_HELP_STRING([--with-fpm-log=@<:@PATH@:>@], [Set the path for php-fpm log file @<:@/var/log/php-fpm.log@:>@]))

	AC_ARG_WITH([fpm-pid],
		AC_HELP_STRING([--with-fpm-pid=@<:@PATH@:>@], [Set the path for php-fpm pid file @<:@/var/run/php-fpm.pid@:>@]))

	AC_ARG_WITH([fpm-user],
		AC_HELP_STRING([--with-fpm-user=@<:@USER@:>@], [Set the user for php-fpm to run as @<:@nobody@:>@]))

	AC_ARG_WITH([fpm-group],
		AC_HELP_STRING([--with-fpm-group=@<:@GRP@:>@], [Set the group for php-fpm to run as @<:@nobody@:>@]))

	fpm_prefix=$ac_default_prefix
	if test $prefix != "NONE" -a $prefix != "" -a $prefix != "no" ; then
		fpm_prefix=$prefix
	else
		prefix=$fpm_prefix
	fi

	if test $exec_prefix = "NONE" -o $exec_prefix = "" -o $exec_prefix = "no" ; then
		exec_prefix=$fpm_prefix
	fi

	if test `echo "$bindir" | grep "exec_prefix"` ; then
		bindir=$exec_prefix/bin
	fi

	fpm_bin_prefix=$fpm_prefix/bin
	if test $bindir != "NONE" -a $bindir != "" -a $bindir != "no" ; then
		fpm_bin_prefix=$bindir
	fi

	if test -z "$PHP_FPM_BIN" -o "$PHP_FPM_BIN" = "yes" -o "$PHP_FPM_BIN" = "no"; then
		php_fpm_bin_path="$fpm_bin_prefix/php-fpm"
	else
		php_fpm_bin_path="$PHP_FPM_BIN"
	fi
	php_fpm_bin=`basename $php_fpm_bin_path`
	php_fpm_bin_dir=`dirname $php_fpm_bin_path`

	if test -z "$with_fpm_port" -o "$with_fpm_port" = "yes" -o "$with_fpm_port" = "no"; then
		php_fpm_port="9000"
	else
		php_fpm_port="$with_fpm_port"
	fi

	if test -z "$with_fpm_conf" -o "$with_fpm_conf" = "yes"; then
		case $host_os in
			freebsd*|dragonfly*)  php_fpm_conf_path="/usr/local/etc/php-fpm.conf" ;;
			*)                    php_fpm_conf_path="/etc/php-fpm.conf" ;;
		esac
	elif test "$with_fpm_conf" = "no"; then
		php_fpm_conf_path=""
	else
		php_fpm_conf_path="$with_fpm_conf"
	fi
	if test -z "$php_fpm_conf_path"; then
		php_fpm_conf=""
		php_fpm_conf_dir=""
	else
		php_fpm_conf=`basename $php_fpm_conf_path`
		php_fpm_conf_dir=`dirname $php_fpm_conf_path`		
	fi
	
	if test -z "$with_fpm_init" -o "$with_fpm_init" = "yes"; then
		case $host_os in
			openbsd*)          php_fpm_init_path="" ;;
			netbsd*)           php_fpm_init_path="/etc/rc.d/php-fpm" ;;
			*bsd*|dragonfly*)  php_fpm_init_path="/usr/local/etc/rc.d/php-fpm" ;;
			*)                 php_fpm_init_path="/etc/init.d/php-fpm" ;;
		esac
		test -f /etc/arch-release && php_fpm_init_path="/etc/rc.d/php-fpm" # arch linux

	elif test "$with_fpm_init" = "no"; then
		php_fpm_init_path=""
	else
		php_fpm_init_path="$with_fpm_init"
	fi
	if test -z "$php_fpm_init_path"; then
		php_fpm_init=""
		php_fpm_init_dir=""
	else
		php_fpm_init=`basename $php_fpm_init_path`
		php_fpm_init_dir=`dirname $php_fpm_init_path`		
	fi

	if test -z "$with_fpm_log" -o "$with_fpm_log" = "yes" -o "$with_fpm_log" = "no"; then
		php_fpm_log_path="/var/log/php-fpm.log"
	else
		php_fpm_log_path="$with_fpm_log"
	fi
	php_fpm_log_dir=`dirname $php_fpm_log_path`

	if test -z "$with_fpm_pid" -o "$with_fpm_pid" = "yes" -o "$with_fpm_pid" = "no"; then
		php_fpm_pid_path="/var/run/php-fpm.pid"
	else
		php_fpm_pid_path="$with_fpm_pid"
	fi
	php_fpm_pid_dir=`dirname $php_fpm_pid_path`

	if test -z "$with_fpm_user" -o "$with_fpm_user" = "yes" -o "$with_fpm_user" = "no"; then
		php_fpm_user="nobody"
	else
		php_fpm_user="$with_fpm_user"
	fi

	if test -z "$with_fpm_group" -o "$with_fpm_group" = "yes" -o "$with_fpm_group" = "no"; then
		php_fpm_group="nobody"
	else
		php_fpm_group="$with_fpm_group"
	fi

])

AC_DEFUN([AC_FPM_CC],
[
	AC_EGREP_CPP([^__INTEL_COMPILER], [__INTEL_COMPILER],
		ICC="no",
		ICC="yes"
	)

	if test "$ICC" = "yes" ; then
		AM_CFLAGS="$AM_CFLAGS -Wall -wd279,310,869,810,981"
	elif test "$GCC" = "yes" ; then
		AM_CFLAGS="$AM_CFLAGS -Wall -Wpointer-arith -Wno-unused-parameter -Wunused-variable -Wunused-value -fno-strict-aliasing"
	fi

	if test -n "$FPM_WERROR" ; then
		AM_CFLAGS="$AM_CFLAGS -Werror"
	fi
])

