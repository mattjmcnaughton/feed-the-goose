from feed_the_goose.config import Settings


def test_allowed_emails_are_a_comma_separated_list(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAILS", " Matt@Example.com, ,b@example.com ")

    assert Settings(_env_file=None).allowed_emails == (
        "matt@example.com",
        "b@example.com",
    )


def test_dev_sign_in_and_dev_routes_are_off_unless_turned_on(monkeypatch):
    monkeypatch.delenv("DEV_SIGN_IN_ENABLED", raising=False)
    monkeypatch.delenv("DEV_ROUTES_ENABLED", raising=False)

    settings = Settings(_env_file=None)

    assert not settings.dev_sign_in_enabled
    assert not settings.dev_routes_enabled
