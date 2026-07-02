<?php

namespace App\DataFixtures;

use Doctrine\Bundle\FixturesBundle\Fixture;
use Doctrine\Bundle\FixturesBundle\FixtureGroupInterface;
use Doctrine\Persistence\ObjectManager;

/**
 * Entry point for fixture groups. Forks replace this with their own entities
 * using Foundry factories (e.g. MemberFactory::createMany(15)).
 *
 * Usage:
 *   bin/console doctrine:fixtures:load --group=staging --no-interaction
 *   bin/console doctrine:fixtures:load --group=dev --no-interaction
 */
class AppFixtures extends Fixture implements FixtureGroupInterface
{
    public static function getGroups(): array
    {
        return ['staging', 'dev'];
    }

    public function load(ObjectManager $manager): void
    {
        // Forks: call your Foundry factories here.
        // Example:
        //   MemberFactory::createMany(15);
        //   ProjectFactory::createMany(5);
        $manager->flush();
    }
}
