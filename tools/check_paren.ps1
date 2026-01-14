$path='C:\Users\PERKY\AndroidStudioProjects\untitled\untitled\lib\screens\inspector_screen.dart'
$s=Get-Content $path -Raw
$stack = New-Object System.Collections.ArrayList
for($i=0;$i -lt $s.Length;$i++) {
  $ch = $s[$i]
  if($ch -eq '(') { [void]$stack.Add($i) }
  elseif($ch -eq ')') {
    if($stack.Count -gt 0) { $stack.RemoveAt($stack.Count-1) }
    else { Write-Output "Unmatched ) at $i"; break }
  }
}
if($stack.Count -gt 0) {
  $last = $stack[$stack.Count-1]
  $line = ($s.Substring(0,$last) -split "`n").Length
  $lastNew = $s.LastIndexOf("`n", $last)
  if($lastNew -eq -1) { $col = $last + 1 } else { $col = $last - $lastNew }
  Write-Output "Unmatched ( at index $last line $line col $col"
} else { Write-Output "All parens matched" }
