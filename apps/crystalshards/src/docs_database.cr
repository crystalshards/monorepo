# The documentation site's database, which crystaldocs owns.
#
# crystaldocs decides which (package, version) combinations need building and
# records each one as a row in doc_build_requests; this app is the thing that
# actually builds them, so it is the only process that can say whether a build
# started, finished or failed. Those columns are written here over a second
# connection rather than mirrored back through a queue or an HTTP callback,
# for the same reason crystaldocs reads this app's registry directly: one
# writer per fact and no copy to fall behind.
#
# The two apps write disjoint halves of the row. crystaldocs writes the
# request (package_name, version, pending, requested_at, attempts, job_id);
# this app writes the outcome (building, succeeded, failed, started_at,
# finished_at, failed_at, last_error). Neither writes the other's columns.
#
# Every query against this database is hand written SQL over a small, stable
# set of columns rather than an Avram model mirrored from crystaldocs, so a
# schema change over there cannot silently retype anything here.
class DocsDatabase < Avram::Database
end
