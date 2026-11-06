"""Startup seeding.

Model endpoints are registered from the provider settings in `.env`
(`model_api_key`, `model_api_base_url`, `answer_model_id`, `agent_model_id`)
on first boot, so a fresh database can answer without a manual
`manage.py add-endpoint`. There's no first-admin-user bootstrapping here:
users are created via `manage.py` (`create-user`, `set-password`), which
talks to the database directly and doesn't need an existing session to do so.

Source rows ARE seeded unconditionally, because they are configuration
rather than data - the four searchable surfaces are a property of the
application, not of a deployment, and an empty `sources` table would make
the search UI look broken rather than unconfigured. Whether a source can
actually answer is a separate question, settled by `POST
/api/sources/{key}/check`.
"""

import logging

from sqlalchemy import func, select

from app.core.config import get_settings
from app.core.db import SessionLocal
from app.models.endpoint import DEFAULT_REASONING_PROFILE, ModelEndpoint
from app.models.source import (
    SOURCE_GITLAB,
    SOURCE_GOOGLE_DRIVE,
    SOURCE_GOOGLE_MAIL,
    SOURCE_POSTGRES_KB,
    Source,
)
from app.services.mcp.semantic import SOURCE_SEMANTIC

logger = logging.getLogger("llmhell.seed")
settings = get_settings()

# key -> (kind, display_name, weight, secret_ref)
#
# Weights are starting points, not measurements. Drive and the KB tables
# hold curated prose, so they tend to answer a question directly; code hits
# and email threads are more often supporting evidence.
_DEFAULT_SOURCES: dict[str, tuple[str, str, float, str | None]] = {
    SOURCE_GOOGLE_DRIVE: ("google_workspace", "Google Drive", 1.0, "google_client_secret"),
    SOURCE_GOOGLE_MAIL: ("google_workspace", "Gmail", 0.8, "google_client_secret"),
    SOURCE_GITLAB: ("gitlab", "GitLab", 1.0, "gitlab_personal_access_token"),
    SOURCE_POSTGRES_KB: ("postgres", "Knowledge base (Postgres)", 1.0, "kb_database_uri"),
    # The index this deployment builds itself, searched by meaning rather than
    # by spelling. Weight 1.0 to start: it has no track record here yet, and
    # weighting it up before measuring would be exactly the guess the eval set
    # exists to replace.
    SOURCE_SEMANTIC: ("semantic", "Semantic index", 1.0, None),
}


async def run_seed() -> None:
    async with SessionLocal() as db:
        await _seed_model_endpoints_from_env(db)
        await _seed_sources(db)
        await db.commit()


def _is_configured(key: str) -> bool:
    """Whether this source has the credentials it needs to answer at all.

    A source seeded enabled but unreachable is not merely useless, it is a
    tax on the ones that work: the fan-out waits for the slowest source, and
    a DNS failure against a container that was never started costs several
    seconds on EVERY search. So an unconfigured source starts disabled and
    the setup docs say to switch it on.
    """
    if key in (SOURCE_GOOGLE_DRIVE, SOURCE_GOOGLE_MAIL):
        return bool(settings.google_client_id and settings.google_client_secret)
    if key == SOURCE_GITLAB:
        return bool(settings.gitlab_personal_access_token)
    if key == SOURCE_POSTGRES_KB:
        return bool(settings.kb_search_tables)
    if key == SOURCE_SEMANTIC:
        # Enabled only once a corpus has been indexed. An empty index answers
        # every search with nothing, which looks exactly like a broken source.
        return settings.semantic_enabled
    return True


async def _seed_sources(db) -> None:
    """Insert any missing default source. Existing rows are left alone -
    an operator who disabled a source or retuned its weight must not have
    that reverted by a restart."""
    existing = set((await db.execute(select(Source.key))).scalars().all())
    added = [
        Source(
            key=key,
            kind=kind,
            display_name=display_name,
            weight=weight,
            secret_ref=secret_ref,
            enabled=_is_configured(key),
            config={},
        )
        for key, (kind, display_name, weight, secret_ref) in _DEFAULT_SOURCES.items()
        if key not in existing
    ]
    if added:
        db.add_all(added)
        for source in added:
            logger.info(
                "Seeded source %s (%s)",
                source.key,
                "enabled" if source.enabled else "disabled - no credentials configured",
            )

    # Help operators notice when a source's configuration has drifted from its
    # row: credentials added but the row is still disabled, or credentials
    # removed but the row is still enabled.
    configured_map = {key: _is_configured(key) for key in _DEFAULT_SOURCES}
    for source in (await db.execute(select(Source).where(Source.key.in_(_DEFAULT_SOURCES)))).scalars().all():
        should_be = configured_map.get(source.key)
        if should_be is not None and source.enabled != should_be:
            if should_be:
                logger.warning(
                    "Source %s has credentials configured but is disabled in the database. "
                    "Enable it with PATCH /api/sources/%s or in the admin UI.",
                    source.key,
                    source.key,
                )
            else:
                logger.warning(
                    "Source %s is enabled but its credentials are no longer configured. "
                    "It will fail on every search until disabled or re-configured.",
                    source.key,
                )


async def _seed_model_endpoints_from_env(db) -> None:
    """Register model endpoints from the provider settings in `.env`, once.

    No-op when an endpoint already exists, or when no API key or answer model
    is configured. A fresh database with `model_api_key` and `answer_model_id`
    set comes up able to answer immediately. The answer model is registered in
    `json_protocol` tools mode and, when `agent_model_id` names a different
    model for @coder, that one is registered in `native` tools mode.
    """
    if not settings.model_api_key or not settings.answer_model_id:
        return
    existing = (await db.execute(select(func.count()).select_from(ModelEndpoint))).scalar_one()
    if existing > 0:
        return

    answer = ModelEndpoint(
        name="Answer",
        base_url=settings.model_api_base_url,
        api_key=settings.model_api_key,
        model_id=settings.answer_model_id,
        role="answer",
        ctx_window=131072,
        tools_mode="json_protocol",
        reasoning_profile=DEFAULT_REASONING_PROFILE,
    )
    db.add(answer)
    seeded = [settings.answer_model_id]
    if settings.agent_model_id and settings.agent_model_id != settings.answer_model_id:
        coder = ModelEndpoint(
            name="Coder",
            base_url=settings.model_api_base_url,
            api_key=settings.model_api_key,
            model_id=settings.agent_model_id,
            role="executor",
            ctx_window=131072,
            tools_mode="native",
            reasoning_profile=DEFAULT_REASONING_PROFILE,
        )
        db.add(coder)
        seeded.append(settings.agent_model_id)
    logger.info("Seeded model endpoints from .env: %s", ", ".join(seeded))
