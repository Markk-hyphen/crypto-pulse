<?php

declare(strict_types=1);

namespace App\Migrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

/**
 * Auto-generated Migration: Please modify to your needs!
 */
final class Version20260702215156 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Add impact_score column to enrichment (2.5 impact score)';
    }

    public function up(Schema $schema): void
    {
        // DEFAULT 0 backfills pre-existing rows (dev/test data enriched before
        // this column existed) — matches the entity's PHP default of 0.0.
        $this->addSql("ALTER TABLE enrichment ADD impact_score DOUBLE PRECISION NOT NULL DEFAULT '0'");
    }

    public function down(Schema $schema): void
    {
        $this->addSql('ALTER TABLE enrichment DROP impact_score');
    }
}
