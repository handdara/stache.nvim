return {
    extend_defaults = function(M)
        assert(M and type(M) == "table")
        M.areas = {
            'seal',
            'thesis',
            'community',
            'learning',
            'hobbies',
            'fitness',
            'community',
            'life',
        }

        M.categories = {
            'electronics',
            'appliances',
            'furniture',
            'clothing',
            'books',
            'media',
            'tools',
            'outdoor',
            'vehicles',
            'art',
            'fitness',
            'instruments',
            'fun',
            'diy',
            'office',
            'health',
            'cooking',
            'organization',
        }

        M.contexts = {
            'laptop',
            'ccrf',
            'home',
            'notebook',
            'cell',
        }

        M.itemTypes = {
            'task',
            'data',
            'contact',
            'inventory',
        }

        M.statuses = {
            'backburner',
            'open', -- "clarify"
            'ready',
            'to-discuss',
            'blocked', -- "waiting"
            'scheduled',
            'in-progress',
            'delayed',
            'archived',
            'closed',
        }

        M.tags = {
            data = { 'heartrate' },
        }

        M.units = {
            temp = { 'farenheit', 'celcius', },
            freq = { 'bpm', 'Hz' },
            velocity = { 'mph', 'mps', 'kph', },
            duration = { 'seconds', 'hours', 'days', 'weeks', 'months', 'years', },
            misc = { 'count', '4-scale' },
        }

        M.favUnits = {
            M.units.temp[1],
            M.units.freq[1],
            M.units.velocity[1],
            M.units.velocity[2],
            M.units.duration[1],
            M.units.duration[2],
            M.units.duration[3],
            M.units.duration[6],
            M.units.misc[1],
            M.units.misc[2],
        }

        M.priorities = {
            '1',
            '2',
            '3',
            '4',
        }

        M.types = {
            date = {
                'birthday',
                'anniversary',
            },
            phone = {
                'cell',
                'home',
                'office',
                'work',
            },
            email = {
                'personal',
                'work',
            },
            address = {
                'personal',
                'office',
            },
        }
    end
}
