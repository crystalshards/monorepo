# The execution trampoline: the boundary every submission crosses.
#
# The runner server re-execs its own binary as
#
#     trycrystal-runner --sandbox-exec -- <command...>
#
# and, between fork and the user's program, this code:
#
#   1. setsid, so the execution is its own process group and the wall-clock
#      timer can kill the whole tree with one signal;
#   2. applies rlimits (address space, CPU, process count, file size,
#      descriptors), which bind from the first instruction of `crystal run`;
#   3. closes every inherited descriptor above 2, so a submission cannot
#      inherit, hijack, or even see the server's listening socket or pipes;
#   4. on Linux in confined mode, installs the no-egress seccomp filter and
#      PROVES it in-process before exec, ported from
#      apps/docs-build/sandbox/no-egress.c: socket(2)/socketpair(2) are
#      restricted to AF_UNIX and AF_NETLINK, io_uring is denied outright
#      (ring ops do their work inside the ring and bypass syscall filters;
#      IORING_OP_SOCKET is a tested bypass of socket-only filters), ptrace
#      and process_vm_* are denied, and no_new_privs is set. The filter
#      survives execve and has no removal interface, so the submission, the
#      compiler, and every child of either hold a network restriction none
#      of them can lift;
#   5. chdir into the per-execution scratch directory and exec the command.
#
# Exit codes 70..72, 74 mirror no-egress so operators can tell a confinement
# refusal from a compiler failure: 70 no_new_privs, 71 filter install,
# 72 filter not proven, 74 exec. The executor surfaces them via stderr.

# Bindings the stdlib does not carry. setrlimit and setsid exist everywhere
# but are not part of LibC; closefrom is the Darwin way to drop inherited
# descriptors (Linux walks /proc/self/fd instead).
lib ExecLib
  fun setrlimit(resource : LibC::Int, rlim : Void*) : LibC::Int
  fun setsid : LibC::Int
end

{% if flag?(:darwin) %}
  # (closefrom is not available on Darwin; close_inherited_fds sweeps the
  # descriptor table instead.)
{% end %}

{% if flag?(:linux) %}
  lib SeccompLib
    struct SockFilter
      code : UInt16
      jt : UInt8
      jf : UInt8
      k : UInt32
    end

    struct SockFprog
      len : UInt16
      filter : SockFilter*
    end

    fun prctl(option : LibC::Int, arg2 : LibC::ULong, arg3 : LibC::ULong,
              arg4 : LibC::ULong, arg5 : LibC::ULong) : LibC::Int
  end
{% end %}

module TryCrystalRunner
  module SandboxExec
    EXIT_NO_NEW_PRIVS = 70
    EXIT_FILTER       = 71
    EXIT_NOT_PROVEN   = 72
    EXIT_EXEC         = 74

    # RLIMIT values differ between Linux and macOS.
    {% if flag?(:darwin) %}
      RLIMIT_CPU    = 0
      RLIMIT_FSIZE  = 1
      RLIMIT_NPROC  = 7
      RLIMIT_NOFILE = 8
      RLIMIT_AS     = 10
    {% else %}
      RLIMIT_CPU    = 0
      RLIMIT_FSIZE  = 1
      RLIMIT_NPROC  = 6
      RLIMIT_NOFILE = 7
      RLIMIT_AS     = 9
    {% end %}

    def self.run(argv : Array(String))
      # Contract: argv (after "--") is the command to exec. Configuration
      # arrives through TC_EXEC_* environment variables, which carry only
      # numbers and paths, never secrets.
      cmd = argv.shift?
      fail(EXIT_EXEC, "sandbox-exec: nothing to exec") unless cmd

      cwd = required_env("TC_EXEC_CWD")

      setsid_or_die
      apply_limits
      # Confined mode does not install the filter in this process. The
      # Crystal runtime is multi-threaded (GC), and a filter installed
      # here via prctl applies to one thread; more importantly, a Crystal
      # BPF port of the docs-build filter hung `crystal run` until the
      # wall timer SIGKILL'd it (exit 137, empty streams). The proven
      # path is the same C helper docs-build already ships: a
      # single-threaded binary that installs the reviewed filter with
      # TSYNC, proves it, and execs. We become that helper.
      c_cmd = cmd.not_nil!
      exec_args = argv
      if confined?
        helper = ENV["TC_NO_EGRESS"]? || "/usr/local/bin/no-egress"
        unless File.executable?(helper)
          fail(EXIT_NOT_PROVEN,
            "sandbox-exec: confined mode requires #{helper}, which is missing or not executable")
        end
        exec_args = [c_cmd] + argv
        c_cmd = helper
      end
      c_argv = ([c_cmd] + exec_args).map(&.to_unsafe)
      c_argv << Pointer(UInt8).null
      close_inherited_fds
      chdir_or_die(cwd)
      if LibC.execvp(c_cmd.to_unsafe, c_argv) == -1
        fail(EXIT_EXEC, "sandbox-exec: exec failed")
      end
    end

    private def self.confined?
      ENV["TC_CONFINED"]? == "1"
    end

    {% unless flag?(:linux) %}
      # Non-Linux builds have no seccomp. The boot gate already refuses
      # confined mode there; this guard is the second lock on the same door,
      # because a trampoline asked to confine and unable to must never
      # continue as if it had.
      private def self.seccomp_and_prove
        fail(EXIT_NOT_PROVEN,
          "sandbox-exec: TC_CONFINED is set but this build has no seccomp support; refusing to run unconfined")
      end
    {% end %}

    private def self.required_env(name)
      value = ENV[name]?
      fail(EXIT_EXEC, "sandbox-exec: #{name} is not set") unless value
      value.not_nil!
    end

    private def self.setsid_or_die
      if ExecLib.setsid == -1
        fail(EXIT_EXEC, "sandbox-exec: setsid failed: #{Errno.value}")
      end
    end

    private def self.chdir_or_die(path)
      if LibC.chdir(path.to_unsafe) == -1
        fail(EXIT_EXEC, "sandbox-exec: chdir failed")
      end
    end

    # Applies every configured rlimit. A limit of 0 means disabled (dev
    # machines where a per-uid limit would count unrelated processes).
    private def self.apply_limits
      set_rlimit(RLIMIT_AS, ENV["TC_LIMIT_AS"]?)
      set_rlimit(RLIMIT_CPU, ENV["TC_LIMIT_CPU"]?)
      set_rlimit(RLIMIT_NPROC, ENV["TC_LIMIT_NPROC"]?)
      set_rlimit(RLIMIT_FSIZE, ENV["TC_LIMIT_FSIZE"]?)
      set_rlimit(RLIMIT_NOFILE, ENV["TC_LIMIT_NOFILE"]?)
    end

    # In confined mode an rlimit that cannot be set is a refused execution:
    # unenforced confinement must never pass as enforced. In ALLOW_UNSAFE
    # mode an inexpressible limit (Darwin rejects every RLIMIT_AS value with
    # EINVAL; verified empirically) degrades to a warning, because dev
    # machines cannot provide what their kernel lacks.
    private def self.set_rlimit(resource, raw)
      return unless raw && raw != "0"

      limit = raw.to_u64?
      fail(EXIT_EXEC, "sandbox-exec: bad rlimit value #{raw.inspect}") unless limit

      rlim = uninitialized LibC::Rlimit
      rlim.rlim_cur = limit
      rlim.rlim_max = limit

      if ExecLib.setrlimit(resource, pointerof(rlim).as(Void*)) == -1
        if confined?
          fail(EXIT_EXEC, "sandbox-exec: setrlimit #{resource} to #{limit} failed: #{Errno.value}")
        end
        # In ALLOW_UNSAFE mode the boot banner already announced unconfined;
        # a per-execution warning would only pollute the user's stderr.
      end
    end

    # Closes every descriptor above 2. The server holds a listening socket
    # and runtime fds; a submission that inherited them could hijack a
    # pending HTTP connection off the listener, so nothing above stdio
    # survives the boundary.
    private def self.close_inherited_fds
      {% if flag?(:linux) %}
        # /proc/self/fd gives exactly the open set; walk and close, skipping
        # the walk's own directory descriptor.
        dir = LibC.opendir("/proc/self/fd")
        if dir
          while (entry = LibC.readdir(dir))
            fd = String.new(entry.value.d_name.to_unsafe).to_i?
            LibC.close(fd) if fd && fd > 2 && fd != LibC.dirfd(dir)
          end
          LibC.closedir(dir)
        else
          sweep_fds
        end
      {% else %}
        # Darwin has neither /proc nor closefrom; sweep the table.
        sweep_fds
      {% end %}
    end

    # Fallback sweep to the soft descriptor limit. EBADF entries are skipped
    # silently; 65_536 bounds the walk on hosts with a huge soft limit.
    private def self.sweep_fds
      if LibC.getrlimit(LibC::RLIMIT_NOFILE, out rl) == 0
        soft = rl.rlim_cur > 65_536_u64 ? 65_536_u64 : rl.rlim_cur
        (3..soft).each { |fd| LibC.close(fd.to_i32!) }
      end
    end

    private def self.exec_command(cmd, args)
      argv = [cmd] + args
      c_argv = argv.map(&.to_unsafe)
      c_argv << Pointer(UInt8).null
      if LibC.execvp(cmd.to_unsafe, c_argv) == -1
        fail(EXIT_EXEC, "sandbox-exec: exec #{cmd} failed: #{Errno.value}")
      end
    end

    private def self.fail(code, message)
      STDERR.puts message
      STDERR.flush
      exit code
    end

    # ------------------------------------------------------------------
    # Linux only: the no-egress seccomp filter.
    # ------------------------------------------------------------------
    {% if flag?(:linux) %}
      PR_SET_NO_NEW_PRIVS = 38
      PR_SET_SECCOMP      = 22
      SECCOMP_MODE_FILTER = 2

      BPF_LD_W_ABS  = 0x20_u16
      BPF_JMP_JEQ_K = 0x15_u16
      BPF_JMP_JGE_K = 0x35_u16
      BPF_RET_K     = 0x16_u16

      SECCOMP_RET_KILL_PROCESS = 0x80000000_u32
      SECCOMP_RET_ERRNO        = 0x00050000_u32
      SECCOMP_RET_ALLOW        = 0x7fff0000_u32
      SECCOMP_RET_DATA         = 0x0000ffff_u32

      EPERM_VALUE        = 1
      EAFNOSUPPORT_VALUE = 97

      AF_UNIX    = 1
      AF_NETLINK = 16

      # seccomp_data layout: nr at 0, arch at 4, args[0] at 16. The address
      # family is an int, so loading the word at args[0] is the same
      # truncation the kernel itself performs.
      OFFSET_NR    = 0
      OFFSET_ARCH  = 4
      OFFSET_ARG0  = 16

      {% if flag?(:aarch64) %}
        AUDIT_ARCH      = 0xC00000B7_u32
        NR_SOCKET     = 198
        NR_SOCKETPAIR = 199
        NR_PTRACE     = 117
        NR_VM_READV   = 270
        NR_VM_WRITEV  = 271
      {% else %}
        AUDIT_ARCH      = 0xC000003E_u32
        NR_SOCKET     = 41
        NR_SOCKETPAIR = 53
        NR_PTRACE     = 101
        NR_VM_READV   = 310
        NR_VM_WRITEV  = 311
      {% end %}

      # io_uring syscall numbers are identical on both architectures.
      NR_IO_URING_SETUP    = 425
      NR_IO_URING_ENTER    = 426
      NR_IO_URING_REGISTER = 427

      X32_SYSCALL_BIT = 0x40000000_u32

      # Indices into the filter, so the relative jumps are derived rather
      # than counted by hand, exactly as in no-egress.c.
      enum Labels
        LoadArch
        TestArch
        KillArch
        LoadNr
        TestX32
        IsSocket
        IsSocketpair
        IsUringSetup
        IsUringEnter
        IsUringRegister
        IsPtrace
        IsVmReadv
        IsVmWritev
        AllowOther
        LoadDomain
        IsUnix
        IsNetlink
        DenyFamily
        DenyPerm
        AllowSocket
        KillX32
        Count
      end

      def self.jt(from : Int32, to : Int32) : UInt8
        (to - from - 1).to_u8
      end

      # Takes any integer and narrows here, so the filter table below reads
      # as BPF rather than as a wall of numeric casts.
      private def self.instruction(code, jt, jf, k)
        SeccompLib::SockFilter.new(
          code: code.to_u16, jt: jt.to_u8, jf: jf.to_u8, k: k.to_u32)
      end

      private def self.build_filter : Array(SeccompLib::SockFilter)
        filter = Array(SeccompLib::SockFilter).new(Labels::Count.value) do
          SeccompLib::SockFilter.new(code: 0, jt: 0, jf: 0, k: 0)
        end

        filter[Labels::LoadArch.value] = instruction(BPF_LD_W_ABS, 0, 0, OFFSET_ARCH)
        filter[Labels::TestArch.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::TestArch.value, Labels::LoadNr.value), 0, AUDIT_ARCH)
        # A syscall under a different personality is not one this filter was
        # reasoned about; it ends the process rather than passing unexamined.
        filter[Labels::KillArch.value] = instruction(BPF_RET_K, 0, 0, SECCOMP_RET_KILL_PROCESS)

        filter[Labels::LoadNr.value] = instruction(BPF_LD_W_ABS, 0, 0, OFFSET_NR)
        # x32 numbers its syscalls with a high bit set while still reporting
        # AUDIT_ARCH_X86_64, so an equality test can be walked straight past;
        # the range is rejected outright. aarch64 has no x32 and no syscall
        # near this number, so the same instruction is correct there.
        filter[Labels::TestX32.value] = instruction(
          BPF_JMP_JGE_K, jt(Labels::TestX32.value, Labels::KillX32.value), 0, X32_SYSCALL_BIT)

        # socket(2) and socketpair(2) carry the address family in arg 0.
        filter[Labels::IsSocket.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsSocket.value, Labels::LoadDomain.value), 0, NR_SOCKET.to_u32)
        filter[Labels::IsSocketpair.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsSocketpair.value, Labels::LoadDomain.value), 0, NR_SOCKETPAIR.to_u32)

        # io_uring submits socket, connect and send as ring opcodes that a
        # filter never sees, so the ring itself is what must not exist.
        filter[Labels::IsUringSetup.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsUringSetup.value, Labels::DenyPerm.value), 0, NR_IO_URING_SETUP.to_u32)
        filter[Labels::IsUringEnter.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsUringEnter.value, Labels::DenyPerm.value), 0, NR_IO_URING_ENTER.to_u32)
        filter[Labels::IsUringRegister.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsUringRegister.value, Labels::DenyPerm.value), 0, NR_IO_URING_REGISTER.to_u32)

        filter[Labels::IsPtrace.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsPtrace.value, Labels::DenyPerm.value), 0, NR_PTRACE.to_u32)
        filter[Labels::IsVmReadv.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsVmReadv.value, Labels::DenyPerm.value), 0, NR_VM_READV.to_u32)
        filter[Labels::IsVmWritev.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsVmWritev.value, Labels::DenyPerm.value), 0, NR_VM_WRITEV.to_u32)

        # Everything else is a normal program doing normal things. This is a
        # filter against leaving the machine, not a syscall allowlist:
        # `crystal run` legitimately compiles, forks, and execs.
        filter[Labels::AllowOther.value] = instruction(BPF_RET_K, 0, 0, SECCOMP_RET_ALLOW)

        filter[Labels::LoadDomain.value] = instruction(BPF_LD_W_ABS, 0, 0, OFFSET_ARG0)
        filter[Labels::IsUnix.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsUnix.value, Labels::AllowSocket.value), 0, AF_UNIX)
        filter[Labels::IsNetlink.value] = instruction(
          BPF_JMP_JEQ_K, jt(Labels::IsNetlink.value, Labels::AllowSocket.value), 0, AF_NETLINK)
        # AF_INET, AF_INET6, AF_PACKET and AF_VSOCK land here. AF_VSOCK
        # matters as much as the internet: on a microVM host it is a channel
        # to the hypervisor, which an internet-shaped block never touches.
        filter[Labels::DenyFamily.value] = instruction(
          BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | (EAFNOSUPPORT_VALUE.to_u32 & SECCOMP_RET_DATA))
        filter[Labels::DenyPerm.value] = instruction(
          BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | (EPERM_VALUE.to_u32 & SECCOMP_RET_DATA))
        filter[Labels::AllowSocket.value] = instruction(BPF_RET_K, 0, 0, SECCOMP_RET_ALLOW)
        filter[Labels::KillX32.value] = instruction(BPF_RET_K, 0, 0, SECCOMP_RET_KILL_PROCESS)

        unless filter.size == Labels::Count.value
          fail(EXIT_FILTER, "sandbox-exec: filter layout drifted: #{filter.size} != #{Labels::Count.value}")
        end

        filter
      end

      private def self.seccomp_and_prove
        if SeccompLib.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0
          fail(EXIT_NO_NEW_PRIVS, "sandbox-exec: PR_SET_NO_NEW_PRIVS failed: #{Errno.value}")
        end

        filter = build_filter

        fprog = SeccompLib::SockFprog.new
        fprog.len = filter.size.to_u16!
        fprog.filter = filter.to_unsafe

        if SeccompLib.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, pointerof(fprog).address, 0, 0) != 0
          fail(EXIT_FILTER, "sandbox-exec: PR_SET_SECCOMP failed: #{Errno.value}")
        end

        prove_filter
      end

      # Proves the filter in this process, after install, before exec. The
      # errno is checked, not merely the failure: AF_PACKET is EPERM even
      # unfiltered on many hosts, and only the filter's own EAFNOSUPPORT is
      # evidence the restriction came from us.
      private def self.prove_filter
        # AF_INET, AF_INET6, AF_PACKET, AF_VSOCK.
        {2, 10, 17, 40}.each do |domain|
          Errno.value = Errno.new(0)
          fd = LibC.socket(domain, 1, 0) # SOCK_STREAM
          if fd >= 0
            LibC.close(fd)
            fail(EXIT_NOT_PROVEN,
              "sandbox-exec: socket domain #{domain} was still created; the filter did not take effect")
          elsif Errno.value != Errno::EAFNOSUPPORT
            fail(EXIT_NOT_PROVEN,
              "sandbox-exec: socket domain #{domain} refused with #{Errno.value}, not EAFNOSUPPORT; cannot prove the filter")
          end
        end
      end
    {% end %}
  end
end
