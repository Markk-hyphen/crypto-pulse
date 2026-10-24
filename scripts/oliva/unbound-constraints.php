<?php
// Constraints sin techo en backend/composer.json (require + require-dev).
//
// Un constraint sin techo (`*`, `>=x`, `^1 || >=3`, `dev-main`) deja que `composer update`
// instale un major nuevo sin aviso: así entró mercure-bundle 0.6 y rompió el build. Además,
// `bump-after-update` convierte un `*` en `>=x`, que parece un rango pensado y es igual de
// abierto. `composer validate` hace este mismo chequeo, pero solo sobre `require`.
//
// Usa la lógica de composer (composer/semver dentro del phar), no una regex propia.
// php y ext-* se ignoran: los fija la imagen Docker, no composer.
//
// Uso: php unbound-constraints.php <composer.json> [<composer phar>]   (default /usr/bin/composer)
// Sale 1 si encuentra alguno (los lista), 0 si no.

$phar = $argv[2] ?? '/usr/bin/composer';
// phar:// necesita la extensión .phar en el nombre del archivo.
$copy = sys_get_temp_dir() . '/oliva-composer-' . getmypid() . '.phar';
copy($phar, $copy);
require "phar://$copy/vendor/autoload.php";

$json = json_decode(file_get_contents($argv[1]), true, flags: JSON_THROW_ON_ERROR);
$parser = new Composer\Semver\VersionParser();
$bad = [];
foreach (['require', 'require-dev'] as $section) {
    foreach ($json[$section] ?? [] as $pkg => $constraint) {
        if (Composer\Repository\PlatformRepository::isPlatformPackage($pkg)) {
            continue;
        }
        if (str_starts_with($constraint, 'dev-')) {
            $bad[] = "$section.$pkg: \"$constraint\" (rama: se mueve sin techo)";
        } elseif ($parser->parseConstraints($constraint)->getUpperBound()->isPositiveInfinity()) {
            $bad[] = "$section.$pkg: \"$constraint\"";
        }
    }
}
unlink($copy);

foreach ($bad as $line) {
    echo $line, PHP_EOL;
}
exit($bad ? 1 : 0);
