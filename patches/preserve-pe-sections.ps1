# Keep explicit section names in Windows executables. Upstream merges sections
# by access class, which discards names supplied with __attribute__((section)).
param([Parameter(Mandatory = $true)][string]$Source)
$path = Join-Path $Source 'tccpe.c'
$text = [IO.File]::ReadAllText($path)
$anchor = 'static int pe_assign_addresses (struct pe_info *pe)'
$condition = 'if (si && c == si->cls && c != sec_debug) {'
if (-not $text.Contains($anchor) -or -not $text.Contains($condition)) {
    throw 'Upstream PE linker changed; review the section preservation patch before building.'
}
$helper = @'
/* TinyCC-builder: merge standard linker sections, preserve explicit names. */
static int pe_standard_section(const char *name)
{
    return !strcmp(name, ".text") || !strcmp(name, ".data")
        || !strcmp(name, ".bss") || !strcmp(name, ".rdata")
        || !strcmp(name, ".xdata") || !strcmp(name, ".init_array")
        || !strcmp(name, ".fini_array") || !strcmp(name, ".ctors")
        || !strcmp(name, ".dtors");
}

'@
$text = $text.Replace($anchor, $helper + "`n" + $anchor)
$text = $text.Replace($condition, @'
if (si && c == si->cls && c != sec_debug
            && ((s->sh_flags & SHF_TLS)
                || (pe_standard_section(s->name) && pe_standard_section(si->name)))) {
'@)
[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
