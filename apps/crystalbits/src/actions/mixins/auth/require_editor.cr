module Auth::RequireEditor
  macro included
    before require_editor
  end

  private def require_editor
    unless EditorCredentials.configured?
      # Fail closed. An unconfigured review queue is a queue nobody can empty,
      # which is the safe direction: content stays in draft.
      return plain_text(EditorCredentials::UNCONFIGURED_MESSAGE, status: 503)
    end

    credentials = EditorCredentials.from_basic_auth(request.headers["Authorization"]?)

    if credentials && EditorCredentials.verify(credentials[0], credentials[1])
      continue
    else
      response.headers["WWW-Authenticate"] = %(Basic realm="#{EditorCredentials::REALM}", charset="UTF-8")
      plain_text "Editor credentials required.", status: 401
    end
  end

  private def current_editor : String
    EditorCredentials.from_basic_auth(request.headers["Authorization"]?).try(&.[0]) || "unknown"
  end
end
