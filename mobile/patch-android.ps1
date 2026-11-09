# Run from the folder that contains kanha_app\  (adds permissions + dev cleartext HTTP to the Android manifest)
$f = "kanha_app\android\app\src\main\AndroidManifest.xml"
$x = Get-Content $f -Raw
if ($x -notmatch "ACCESS_FINE_LOCATION") {
  $perm = '<uses-permission android:name="android.permission.INTERNET"/>' + "`n    " +
          '<uses-permission android:name="android.permission.CAMERA"/>' + "`n    " +
          '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>' + "`n    "
  $x = $x -replace '<application', ($perm + '<application android:usesCleartextTraffic="true"')
  Set-Content -Path $f -Value $x -Encoding UTF8
  Write-Host "Manifest patched."
} else { Write-Host "Already patched." }
