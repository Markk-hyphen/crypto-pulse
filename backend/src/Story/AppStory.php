<?php

namespace App\Story;

use Zenstruck\Foundry\Attribute\AsFixture;
use Zenstruck\Foundry\Story;

/**
 * Optional Story entry point. Forks can use this to group factory calls
 * into named scenarios (e.g. "main" story for staging).
 *
 * Usage from AppFixtures:
 *   AppStory::load();
 */
#[AsFixture(name: 'main')]
final class AppStory extends Story
{
    public function build(): void
    {
        // Forks: orchestrate factories into a scenario here.
        // Example:
        //   MemberFactory::createMany(15);
        //   ProjectFactory::createMany(5);
    }
}
