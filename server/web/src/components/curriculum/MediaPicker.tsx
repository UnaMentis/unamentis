
import React, { useState } from 'react';
import { Search, Image as ImageIcon, Loader2, Plus, Check } from 'lucide-react';
import { MediaItem } from '@/types/curriculum';

// Mock data for "functional" demo purposes since we don't have a real API key
// In a real app, this would fetch from Unsplash/Pexels/Openverse
const MOCK_IMAGES = [
    { id: '1', url: 'https://images.unsplash.com/photo-1518770660439-4636190af475', title: 'Neural Network', author: 'Google DeepMind' },
    { id: '2', url: 'https://images.unsplash.com/photo-1555949963-ff9fe0c870eb', title: 'Code Screen', author: 'Markus Spiske' },
    { id: '3', url: 'https://images.unsplash.com/photo-1550751827-4bd374c3f58b', title: 'Cybersecurity', author: 'Jefferson Santos' },
    { id: '4', url: 'https://images.unsplash.com/photo-1544256718-3bcf237f3974', title: 'Library', author: 'Giammarco' },
    { id: '5', url: 'https://images.unsplash.com/photo-1509062522246-3755977927d7', title: 'Education', author: 'Element5 Digital' },
    { id: '6', url: 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5', title: 'Matrix Code', author: 'Markus Spiske' },
    { id: '7', url: 'https://images.unsplash.com/photo-1531297461136-82lw8u8z5g2', title: 'Technology', author: 'Alex Knight' },
    { id: '8', url: 'https://images.unsplash.com/photo-1451187580459-43490279c0fa', title: 'Global Network', author: 'NASA' },
    { id: '9', url: 'https://images.unsplash.com/photo-1517694712202-14dd9538aa97', title: 'Coding Laptop', author: 'Clément H.' },
    { id: '10', url: 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158', title: 'Laptop working', author: 'Windows' },
];

interface MediaPickerProps {
    onSelect: (media: Partial<MediaItem>) => void;
    onClose: () => void;
}

export const MediaPicker: React.FC<MediaPickerProps> = ({ onSelect, onClose }) => {
    const [query, setQuery] = useState('');
    const [loading, setLoading] = useState(false);
    const [results, setResults] = useState(MOCK_IMAGES);
    const [selectedId] = useState<string | null>(null);

    const handleSearch = (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        // Simulate API latency
        setTimeout(() => {
            // Simple filter for mock
            const filtered = MOCK_IMAGES.filter(img =>
                img.title.toLowerCase().includes(query.toLowerCase()) ||
                img.author.toLowerCase().includes(query.toLowerCase())
            );
            setResults(filtered);
            setLoading(false);
        }, 600);
    };

    const handleSelect = (img: typeof MOCK_IMAGES[0]) => {
        onSelect({
            type: 'image',
            url: img.url,
            title: img.title,
            alt: `Image of ${img.title} by ${img.author}`,
            mimeType: 'image/jpeg'
        });
        onClose();
    };

    return (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-in">
            <div className="bg-slate-900 border border-slate-700 rounded-xl shadow-2xl w-full max-w-4xl max-h-[85vh] flex flex-col overflow-hidden">

                {/* Header */}
                <div className="p-6 border-b border-slate-800 flex justify-between items-center bg-slate-900/50">
                    <div>
                        <h2 className="text-xl font-semibold text-white">Select Image</h2>
                        <p className="text-slate-400 text-sm">Find free-to-use images from the creative commons.</p>
                    </div>
                    <button onClick={onClose} className="p-2 hover:bg-slate-800 rounded-full transition-colors text-slate-400 hover:text-white">
                        <Plus className="rotate-45" />
                    </button>
                </div>

                {/* Search Bar */}
                <div className="p-4 border-b border-slate-800 bg-slate-900/30">
                    <form onSubmit={handleSearch} className="relative">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
                        <input
                            type="text"
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            placeholder="Search for photos (e.g., 'artificial intelligence', 'classroom')..."
                            className="w-full bg-slate-800 border-slate-700 text-white pl-10 pr-4 py-3 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:outline-none transition-all placeholder:text-slate-500"
                            autoFocus
                        />
                    </form>
                </div>

                {/* Grid */}
                <div className="flex-1 overflow-y-auto p-4 custom-scrollbar">
                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64 text-slate-500">
                            <Loader2 className="animate-spin mb-3" size={32} />
                            <p>Searching visual assets...</p>
                        </div>
                    ) : results.length > 0 ? (
                        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                            {results.map((img) => (
                                <div
                                    key={img.id}
                                    className="group relative aspect-video bg-slate-800 rounded-lg overflow-hidden cursor-pointer border border-slate-700 hover:border-indigo-500 transition-all hover:shadow-lg hover:shadow-indigo-500/20"
                                    onClick={() => handleSelect(img)}
                                >
                                    <img src={img.url} alt={img.title} className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110" />
                                    <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity flex flex-col justify-end p-3">
                                        <span className="text-white font-medium text-sm truncate">{img.title}</span>
                                        <span className="text-slate-300 text-xs truncate">by {img.author}</span>
                                    </div>
                                    {selectedId === img.id && (
                                        <div className="absolute top-2 right-2 bg-indigo-500 rounded-full p-1 shadow-lg">
                                            <Check size={12} className="text-white" />
                                        </div>
                                    )}
                                </div>
                            ))}
                        </div>
                    ) : (
                        <div className="flex flex-col items-center justify-center h-64 text-slate-500">
                            <ImageIcon size={48} className="mb-4 opacity-50" />
                            <p>No results found for &quot;{query}&quot;</p>
                        </div>
                    )}
                </div>

                {/* Footer */}
                <div className="p-4 border-t border-slate-800 bg-slate-900/50 flex justify-between items-center text-xs text-slate-500">
                    <span>Powered by Unsplash Source (Mock)</span>
                    <div className="flex gap-2">
                        <button onClick={onClose} className="px-4 py-2 rounded-lg hover:bg-slate-800 text-slate-300 transition-colors">Cancel</button>
                    </div>
                </div>
            </div>
        </div>
    );
};
