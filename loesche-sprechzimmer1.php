<?php
header("Content-Type: text/plain; charset=utf-8");
header("Cache-Control: no-store");

$path = "/var/www/html/sprechzimmer1.gdt";
if (substr($path, -4) !== ".gdt") {
  http_response_code(500);
  echo "bad extension\n";
  exit;
}
if (!file_exists($path)) {
  http_response_code(204);
  echo "no file\n";
  exit;
}
if (@unlink($path)) {
  http_response_code(200);
  echo "deleted\n";
  exit;
}
http_response_code(500);
echo "delete failed\n";
