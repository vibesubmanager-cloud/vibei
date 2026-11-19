from flask import Blueprint

api_v1 = Blueprint("api_v1", __name__)

from . import routes  # noqa: E402,F401
from . import admin_routes  # noqa: E402,F401
