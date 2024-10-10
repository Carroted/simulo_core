local saved = nil;

-- save data just has our hinge, we save it unchanged
-- we got it originally from the hinge tool passing it to add_attachment

function on_start(data)
    saved = data;
end;
function on_save()
    return saved;
end;

function on_destroy()
    if not saved.hinge:is_destroyed() then
        saved.hinge:destroy();
    end;
end;

function on_update()
    if saved.hinge:is_destroyed() then
        self:destroy();
    end;
end;
