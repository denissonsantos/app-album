<?php
/**
 * Kapitchi Zend Framework 2 Modules
 *
 * @copyright Copyright (c) 2012-2014 Kapitchi Open Source Community (http://kapitchi.com/open-source)
 * @license   http://opensource.org/licenses/MIT MIT
 */

return [
    'file-manager' => array(
        'filesystem-manager' => [
            'config' => [
                'album_item' => [
                    'type' => 'local',
                    'options' => [
                        'path' => 'data/album-item'
                    ]
                ],
                'album_item_thumbnail' => [
                    'type' => 'local',
                    'options' => [
                        'path' => 'data/album-item-thumbnail'
                    ]
                ],
                'file_thumbnail' => [
                    'type' => 'local',
                    'options' => [
                        'path' => 'public/file_thumbnail'
                    ]
                ]
            ]
        ],
        'thumbnail-types' => [
            'fullsize' => [
                'filter' => 'fit',
                'width' => 1920,
                'height' => 1080
            ],
            'album' => [
                'filter' => 'fit',
                'width' => 256,
                'height' => 144
            ],
            'gallery_item' => [
                'filter' => 'fit',
                'width' => 128,
                'height' => 72
            ]
        ]
    ),
];